
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.parallelparser;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cpptree;
import cppconv.runcppcommon;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.conv;
import std.range;
import std.stdio;
import std.typecons;

alias Location = LocationX;
alias Tree = CppParseTree;
alias TreeArray = CppParseTreeArray;

alias getDummyGrammarInfo2 = getDummyGrammarInfo!20050;

void dumpStates(alias P)(ref P.PushParser!(CppParseTreeCreator!(P), string) pushParser,
        LogicSystem logicSystem, string indent)
{
    foreach (n; pushParser.stackTops)
    {
        foreach (e; n.previous)
        {
            if (e.node.state == 0)
            {
                if (e.data.nonterminal.nonterminalID == P.nonterminalIDFor!"DeclarationSeq")
                {
                    auto arr = n.previous[0].data.nonterminal.get!(P.nonterminalIDFor!"DeclarationSeq");
                    foreach (i, x; arr.trees)
                    {
                        writeln(indent, "  arr[", i, "]: ");
                        CodeWriter code;
                        code.incIndent(indent.length / 2);
                        parseTreeToCode(code, x, logicSystem, logicSystem.true_);
                        writeln(code.data);
                    }
                }
                else if (e.data.nonterminal.nonterminalID == P.nonterminalIDFor!"TranslationUnit")
                {
                    writeln(indent, "  tu:");
                    CodeWriter code;
                    code.incIndent(indent.length / 2);
                    parseTreeToCode(code, n.previous[0].data.nonterminal.get!(
                            P.nonterminalIDFor!"TranslationUnit"), logicSystem, logicSystem.true_);
                    writeln(code.data);
                }
            }
        }
    }
}

Tree addArrayElem(Tree tree, Tree el)
{
    if (!tree.isValid)
        return Tree.init;

    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        return tree;
    }
    else if (tree.nodeType == NodeType.merged && tree.nonterminalID >= 30_000)
    {
        return tree;
    }
    else if (tree.nodeType == NodeType.array)
    {
        return createArrayTree(tree.childs ~ el);
    }
    else if (tree.nodeType == NodeType.token)
    {
        if (tree.name == "")
            return Tree.init;
        return tree;
    }
    else
    {
        foreach_reverse (i; 0 .. tree.childs.length)
        {
            Tree newChild = addArrayElem(tree.childs[i], el);
            if (!newChild.isValid)
                continue;
            if (newChild.this_ is tree.childs[i].this_)
                return tree;
            Tree[] newChilds = tree.childs.dup;
            newChilds[i] = newChild;

            Tree r = Tree(tree.name, tree.nonterminalID, tree.productionID,
                    tree.nodeType, newChilds, treeAllocator);
            r.grammarInfo = tree.grammarInfo;
            r.setStartEnd(tree.start, tree.end);
            return r;
        }

        return Tree.init;
    }
}

bool isMergeable(alias P)(P.PushParser!(CppParseTreeCreator!(P), string)
        .StackNode* nodeA, P.PushParser!(CppParseTreeCreator!(P), string)
        .StackNode* nodeB, bool inTail = false)
{
    alias PushParser = P.PushParser!(CppParseTreeCreator!(P), string);
    if (nodeA is nodeB)
        return true;
    if (nodeA.state != nodeB.state)
        return false;
    if (nodeA.previous.length != nodeB.previous.length)
        return false;
    foreach (i; 0 .. nodeA.previous.length)
    {
        PushParser.StackEdge* edgeA = nodeA.previous[i];
        PushParser.StackEdge* edgeB = nodeB.previous[i];
        if (edgeA.data.isToken != edgeB.data.isToken) // should not happen
            return false;
        if (edgeA.data is edgeB.data)
        {
            if (//edgeA.node !is edgeB.node
                !isMergeable!P(edgeA.node, edgeB.node, inTail))
                return false;
        }
        else if (edgeA.data.isToken)
        {
            if (edgeA.data !is edgeB.data)
                return false;
            if (//edgeA.node !is edgeB.node
                !isMergeable!P(edgeA.node, edgeB.node, inTail))
                return false;
        }
        else
        {
            if (edgeA.data.nonterminal.nonterminalID != edgeB.data.nonterminal.nonterminalID)
                return false;

            bool isNullEdge;
            bool isEqualTreeEdge;
            if (edgeA.data.nonterminal.isType!string)
            {
                auto treeA = edgeA.data.nonterminal.getT!string;
                auto treeB = edgeB.data.nonterminal.getT!string;

                if (treeA == treeB)
                    isEqualTreeEdge = true;
                else
                    return false;
            }
            else if (edgeA.data.nonterminal.isType!Tree)
            {
                auto treeA = edgeA.data.nonterminal.getT!Tree;
                auto treeB = edgeB.data.nonterminal.getT!Tree;

                if (!treeA.isValid && !treeB.isValid)
                    isNullEdge = true;
                if (equalTrees(treeA, treeB))
                    isEqualTreeEdge = true;
            }
            else if (edgeA.data.nonterminal.isType!TreeArray)
            {
                auto treeA = edgeA.data.nonterminal.getT!TreeArray;
                auto treeB = edgeB.data.nonterminal.getT!TreeArray;

                if (treeA.length == 0 && treeB.length == 0)
                    isNullEdge = true;
            }
            else
                return false;
            if (isNullEdge || isEqualTreeEdge)
            {
                if (!isMergeable!P(edgeA.node, edgeB.node, inTail))
                    return false;
            }
            else
            {
                if (inTail || !isMergeable!P(edgeA.node, edgeB.node, true))
                    return false;
            }
        }
    }
    return true;
}

bool canMerge(alias P)(ref P.PushParser!(CppParseTreeCreator!(P), string) pushParserA,
        ref P.PushParser!(CppParseTreeCreator!(P), string) pushParserB)
{
    if (pushParserA.stackTops.length != pushParserB.stackTops.length)
        return false;
    if (pushParserA.acceptedStackTops.length != pushParserB.acceptedStackTops.length)
        return false;

    foreach (i; 0 .. pushParserA.stackTops.length)
        if (!isMergeable!P(pushParserA.stackTops[i], pushParserB.stackTops[i]))
            return false;
    foreach (i; 0 .. pushParserA.acceptedStackTops.length)
        if (!isMergeable!P(pushParserA.acceptedStackTops[i], pushParserB.acceptedStackTops[i]))
            return false;
    return true;
}

void doMerge(alias P)(ref P.PushParser!(CppParseTreeCreator!(P), string) pushParserA,
        ref P.PushParser!(CppParseTreeCreator!(P), string) pushParserB,
        ref P.PushParser!(CppParseTreeCreator!(P), string) pushParserOut,
        immutable(Formula)*[2] childConditions2, LogicSystem logicSystem,
        immutable(Formula)* anyErrorCondition, immutable(Formula)* contextCondition)
{
    alias PushParser = P.PushParser!(CppParseTreeCreator!(P), string);
    PushParser.StackNode*[PushParser.StackNode*] mergeDone;

    PushParser.StackNode* mergeNodes(PushParser.StackNode* nodeA, PushParser.StackNode* nodeB)
    {
        if (nodeA is nodeB)
            return nodeA;
        if (nodeA in mergeDone)
            return mergeDone[nodeA];
        PushParser.StackNode* newNode = new PushParser.StackNode(nodeA.state);
        mergeDone[nodeA] = newNode;
        newNode.previous.length = nodeA.previous.length;
        foreach (i; 0 .. nodeA.previous.length)
        {
            PushParser.StackEdge* edgeA = nodeA.previous[i];
            PushParser.StackEdge* edgeB = nodeB.previous[i];

            PushParser.StackNode* prevNode = mergeNodes(edgeA.node, edgeB.node);
            PushParser.StackEdge* newEdge = new PushParser.StackEdge(prevNode,
                    null, edgeA.reduceDone);
            if (edgeA.data is edgeB.data)
            {
                newEdge.data = edgeA.data;
            }
            else if (edgeA.data.isToken)
            {
                newEdge.data = new PushParser.StackEdgeData(edgeA.data.isToken, edgeA.data.start);
                newEdge.data.token = edgeA.data.token;
            }
            else
            {
                newEdge.data = new PushParser.StackEdgeData(edgeA.data.isToken, edgeA.data.start);

                if (edgeA.data.nonterminal.isType!string)
                {
                    auto treeA = edgeA.data.nonterminal.getT!string;
                    auto treeB = edgeB.data.nonterminal.getT!string;
                    assert(treeA == treeB, text("\"", treeA, "\" \"", treeB, "\""));
                    newEdge.data.start = edgeA.data.start;
                    newEdge.data.nonterminal = edgeA.data.nonterminal;
                }
                else if (edgeA.data.nonterminal.isType!Tree)
                {
                    auto treeA = edgeA.data.nonterminal.getT!Tree;
                    auto treeB = edgeB.data.nonterminal.getT!Tree;
                    if (!treeA.isValid && !treeB.isValid)
                    {
                        newEdge.data.start = edgeA.data.start;
                        newEdge.data.nonterminal = edgeA.data.nonterminal;
                    }
                    else
                    {
                        auto newTree = mergeTrees(treeA, treeB, childConditions2, logicSystem,
                                anyErrorCondition, contextCondition, MergeFlags.none);
                        newEdge.data.start = newTree.start;
                        newEdge.data.nonterminal = CppParseTreeCreator!(P)
                            .NonterminalUnionAny.create(edgeA.data.nonterminal.nonterminalID,
                                    newTree);
                    }
                }
                else if (edgeA.data.nonterminal.isType!TreeArray)
                {
                    auto arrA = edgeA.data.nonterminal.getT!TreeArray;
                    auto arrB = edgeB.data.nonterminal.getT!TreeArray;
                    if (arrA.length == 0 && arrB.length == 0)
                    {
                        newEdge.data.start = edgeA.data.start;
                        newEdge.data.nonterminal = edgeA.data.nonterminal;
                    }
                    else
                    {
                        Location nonterminalStart = minLoc(edgeA.data.start, edgeB.data.start);
                        static if (is(typeof(arrA.end)))
                        {
                            Location nonterminalEnd = maxLoc(arrA.end, arrB.end);
                        }
                        else
                        {
                            Location nonterminalEnd = maxLoc(edgeA.data.start + arrA.inputLength,
                                    edgeB.data.start + arrB.inputLength);
                        }

                        TreeArray arr2;
                        arr2.trees = mergeArrays(arrA.trees, arrB.trees, childConditions2, logicSystem,
                                anyErrorCondition, contextCondition, MergeFlags.none, 0);
                        static if (is(typeof(arrA.end)))
                            arr2.end = nonterminalEnd;
                        else
                            arr2.inputLength = nonterminalEnd - nonterminalStart;

                        newEdge.data.start = nonterminalStart;
                        newEdge.data.nonterminal = CppParseTreeCreator!(P)
                            .NonterminalUnionAny.create(edgeA.data.nonterminal.nonterminalID, arr2);
                    }
                }
                else
                    assert(false, "Bug: isMergeable and doMerge not consistent");
            }
            newNode.previous[i] = newEdge;
        }
        return newNode;
    }

    foreach (i; 0 .. pushParserOut.stackTops.length)
        pushParserOut.stackTops[i] = mergeNodes(pushParserA.stackTops[i], pushParserB.stackTops[i]);
    foreach (i; 0 .. pushParserOut.acceptedStackTops.length)
        pushParserOut.acceptedStackTops[i] = mergeNodes(pushParserA.acceptedStackTops[i],
                pushParserB.acceptedStackTops[i]);

    if (pushParserA.lastTokenEnd > pushParserB.lastTokenEnd)
        pushParserOut.lastTokenEnd = pushParserA.lastTokenEnd;
    else
        pushParserOut.lastTokenEnd = pushParserB.lastTokenEnd;
}
