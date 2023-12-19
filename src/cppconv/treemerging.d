
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.treemerging;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.filecache;
import cppconv.locationstack;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import std.algorithm;
import std.array;
import std.conv;
import std.typecons;

enum MergeFlags
{
    none = 0,
    nullOnTreeCondition = 1,
    nullOnTreeConditionRec = 2,

    recursiveFlags = nullOnTreeConditionRec
}

Tree[] mergeArrays(Tree[] arrA, Tree[] arrB, immutable(Formula)*[2] childConditions,
        LogicSystem logicSystem, immutable(Formula)* anyErrorCondition,
        immutable(Formula)* contextCondition, MergeFlags flags, size_t indentNum = 4)
{
    size_t commonChilds;
    while (commonChilds < arrA.length && commonChilds < arrB.length
            && equalTrees(arrA[commonChilds], arrB[commonChilds]))
        commonChilds++;
    size_t commonChilds2;
    while (commonChilds2 < arrA.length - commonChilds && commonChilds2 < arrB.length - commonChilds
            && equalTrees(arrA[$ - 1 - commonChilds2], arrB[$ - 1 - commonChilds2]))
        commonChilds2++;

    Tree[] newChilds;
    newChilds ~= arrA[0 .. commonChilds];

    size_t uncommonChildsA = arrA.length - commonChilds - commonChilds2;
    size_t uncommonChildsB = arrB.length - commonChilds - commonChilds2;

    if (arrA.length > commonChilds + commonChilds2 || arrB.length > commonChilds + commonChilds2)
    {
        static Appender!(Tuple!(Tree, immutable(Formula)*, byte)[]) treesApp;
        size_t treesAppStartSize = treesApp.data.length;
        scope (exit)
            treesApp.shrinkTo(treesAppStartSize);

        if (uncommonChildsA >= 1)
        {
            foreach (t1; arrA[commonChilds .. $ - commonChilds2])
            {
                extractConditionTree!((t, c) => treesApp.put(tuple!(Tree,
                        immutable(Formula)*, byte)(t, c, byte(1))))(t1,
                        childConditions[0], logicSystem, true, true);
            }
        }

        if (uncommonChildsB >= 1)
        {
            foreach (t1; arrB[commonChilds .. $ - commonChilds2])
            {
                extractConditionTree!((t, c) => treesApp.put(tuple!(Tree,
                        immutable(Formula)*, byte)(t, c, byte(2))))(t1,
                        childConditions[1], logicSystem, true, true);
            }
        }

        Tuple!(Tree, immutable(Formula)*, byte)[] treesA = treesApp.data[treesAppStartSize .. $];

        treesA.sort!((a, b) => a[0].start.opCmp2(b[0].start, true) < 0);

        foreach (i1; 0 .. treesA.length)
        {
            auto t1 = treesA[i1][0];
            auto cond1 = treesA[i1][1];
            if (cond1 is null)
                continue;
            foreach (i2; i1 + 1 .. treesA.length)
            {
                auto t2 = treesA[i2][0];
                auto cond2 = treesA[i2][1];
                if (cond2 is null)
                    continue;
                if (t2.start > t1.end)
                    break;

                if (!logicSystem.and(cond1, cond2).isFalse)
                    continue;

                if (treesOverlapping(t1, t2))
                {
                    bool hasConflict;
                    foreach (i4; i1 + 1 .. treesA.length)
                    {
                        auto t4 = treesA[i4][0];
                        auto cond4 = treesA[i4][1];
                        if (i4 == i2)
                            continue;
                        if (cond4 is null)
                            continue;
                        if (t4.start > t1.end)
                            break;

                        if (treesOverlapping(t1, t4) && !logicSystem.and(cond4, cond2).isFalse)
                        {
                            hasConflict = true;
                            break;
                        }
                        if (treesOverlapping(t2, t4) && !logicSystem.and(cond4, cond1).isFalse)
                        {
                            hasConflict = true;
                            break;
                        }
                    }
                    if (hasConflict)
                        continue;

                    auto newContextCondition = logicSystem.and(contextCondition,
                            logicSystem.or(cond1, cond2));
                    auto cond3 = logicSystem.simplify(logicSystem.distributeOrSimple(cond1, cond2));
                    MergeFlags flags2 = (flags & MergeFlags.recursiveFlags)
                        | MergeFlags.nullOnTreeCondition;
                    auto t3 = mergeTrees(t1, t2, [cond1, cond2], logicSystem,
                            anyErrorCondition, newContextCondition, flags2, indentNum + 1);

                    if (!t3.isValid)
                    {
                        continue;
                    }
                    assert(t3.nonterminalID != CONDITION_TREE_NONTERMINAL_ID);

                    treesA[i1][0] = t3;
                    treesA[i1][1] = cond3;

                    t1 = t3;
                    cond1 = cond3;

                    treesA[i2][0] = Tree.init;
                    treesA[i2][1] = null;
                }
            }
        }
        {
            size_t iOut = 0;
            foreach (iIn; 0 .. treesA.length)
            {
                if (treesA[iIn][1]!is null)
                {
                    treesA[iOut] = treesA[iIn];
                    iOut++;
                }
            }
            treesA = treesA[0 .. iOut];
        }

        Tree[] arrTrees;

        while (true)
        {
            static Appender!(Tree[]) trees3App;
            trees3App.clear();
            static Appender!(immutable(Formula)*[]) conditions3App;
            conditions3App.clear();
            immutable(Formula)* conditionAny = logicSystem.false_;
            while (true)
            {
                static Appender!(Tree[]) trees2App;
                trees2App.clear();
                immutable(Formula)* conditionHere;
                while (treesA.length && !treesA[0][0].isValid)
                    treesA = treesA[1 .. $];

                size_t firstI;
                // get first tree
                foreach (i, ref t; treesA)
                {
                    if (!t[0].isValid)
                        continue;
                    if (!logicSystem.and(conditionAny, t[1]).isFalse)
                        break;
                    if (trees3App.data.length
                            && trees3App.data[0].location.nonMacroLocation
                                .context !is t[0].location.nonMacroLocation.context)
                        break;
                    trees2App.put(t[0]);
                    t[0] = Tree.init;
                    conditionHere = t[1];
                    t[1] = null;
                    firstI = i;
                    break;
                }
                if (trees2App.data.length == 0)
                    break;
                foreach (ref t; treesA[firstI + 1 .. $])
                {
                    if (!t[0].isValid)
                        break;
                    if (t[1] is conditionHere && t[0].start.context is trees2App
                            .data[0].start.context)
                    {
                        trees2App.put(t[0]);
                        t[0] = Tree.init;
                        t[1] = null;
                    }
                    else if (!logicSystem.and(t[1], conditionHere).isFalse)
                    {
                        break;
                    }
                }
                auto trees2 = trees2App.data;
                if (trees2.length == 1)
                    trees3App.put(trees2[0]);
                else
                    trees3App.put(createArrayTreeSimple(trees2.dup));
                conditions3App.put(conditionHere);
                conditionAny = logicSystem.simplify(logicSystem.distributeOrSimple(conditionAny,
                        conditionHere));
            }
            if (trees3App.data.length == 0)
                break;
            if (!conditionAny.isTrue && !(logicSystem.or(conditionAny,
                    logicSystem.or(childConditions[0], childConditions[1]).negated)).isTrue)
            {
                trees3App.put(createArrayTree([]));
                conditions3App.put(conditionAny.negated);
            }
            Tree t3;
            if (trees3App.data.length == 1)
            {
                t3 = trees3App.data[0];
            }
            else
            {
                foreach (ref c; conditions3App.data)
                    c = logicSystem.removeRedundant(c, contextCondition);
                auto t3c = new ConditionTreeStruct(trees3App.data.dup,
                        conditions3App.data.dup, "#PPIf");
                t3 = t3c.toTree;
            }
            arrTrees ~= t3;
        }
        foreach (t; treesA)
            assert(!t[0].isValid);

        newChilds ~= arrTrees;
    }
    newChilds ~= arrA[$ - commonChilds2 .. $];
    return newChilds;
}

bool areTreesCompatible(Tree treeA2, Tree treeB2)
{
    return treeA2.isValid && treeB2.isValid && treeA2.nonterminalID == treeB2.nonterminalID
        && treeA2.productionID == treeB2.productionID
        && treeA2.nodeType.among(NodeType.nonterminal, NodeType.merged)
        && treeB2.nodeType.among(NodeType.nonterminal, NodeType.merged)
        && treeA2.name == treeB2.name
        && treeA2.nonterminalID != CONDITION_TREE_NONTERMINAL_ID
        && treeB2.nonterminalID != CONDITION_TREE_NONTERMINAL_ID
        && treeA2.childs.length == treeB2.childs.length && {
        size_t numDifferent;
        foreach (i; 0 .. treeA2.childs.length)
        {
            if (treeA2.childs[i]!is treeB2.childs[i])
            {
                if (!treeA2.childs[i].isValid || !treeB2.childs[i].isValid)
                    return false;
                if (treeA2.childs[i].isToken != treeB2.childs[i].isToken)
                {
                    numDifferent++;
                    continue;
                }

                if (treeA2.childs[i].isToken)
                {
                    if (treeA2.childs[i].content != treeB2.childs[i].content
                            || treeA2.childs[i].start != treeB2.childs[i].start)
                        return false;
                }
                else if (equalTrees(treeA2.childs[i], treeB2.childs[i]))
                {
                }
                else
                    numDifferent++;
            }
        }
        return numDifferent <= 1;
    }();
}

Tree mergeCompatibleTrees(Tree treeA2, Tree treeB2, immutable(Formula)*[2] childConditions,
        LogicSystem logicSystem, immutable(Formula)* anyErrorCondition,
        immutable(Formula)* contextCondition, MergeFlags flags, size_t indentNum = 4)
{
    Location nonterminalStart = minLoc(treeA2.start, treeB2.start);
    Location nonterminalEnd = maxLoc(treeA2.end, treeB2.end);

    Tree[] newChilds;
    newChilds.length = treeA2.childs.length;
    bool badChildMerge;
    foreach (i; 0 .. treeA2.childs.length)
    {
        if (treeA2.childs[i] is treeB2.childs[i] || (treeA2.childs[i].isToken
                && treeA2.childs[i].content == treeB2.childs[i].content
                && treeA2.childs[i].start == treeB2.childs[i].start))
            newChilds[i] = treeA2.childs[i];
        else
        {
            auto newContextCondition = logicSystem.and(contextCondition,
                    logicSystem.or(childConditions[0], childConditions[1]));
            newChilds[i] = mergeTrees(treeA2.childs[i], treeB2.childs[i],
                    childConditions, logicSystem, anyErrorCondition,
                    newContextCondition, flags & MergeFlags.recursiveFlags, indentNum + 4);
            if (!newChilds[i].isValid && treeA2.childs[i].isValid)
                badChildMerge = true;
        }
    }
    if (badChildMerge)
        return Tree.init;
    Tree tree2;
    {
        tree2 = Tree(treeA2.name, treeA2.nonterminalID, treeA2.productionID,
                treeA2.nodeType, newChilds, treeAllocator);
    }
    tree2.grammarInfo = treeA2.grammarInfo;
    tree2.setStartEnd(nonterminalStart, nonterminalEnd);
    return tree2;
}

Tree mergeTrees(Tree treeA, Tree treeB, immutable(Formula)*[2] childConditions,
        LogicSystem logicSystem, immutable(Formula)* anyErrorCondition,
        immutable(Formula)* contextCondition, MergeFlags flags, size_t indentNum = 4)
{
    static Appender!(Tuple!(Tree, immutable(Formula)*)[]) treesAppA, treesAppB;
    size_t treesAppAStartSize = treesAppA.data.length;
    size_t treesAppBStartSize = treesAppB.data.length;
    scope (exit)
    {
        treesAppA.shrinkTo(treesAppAStartSize);
        treesAppB.shrinkTo(treesAppBStartSize);
    }

    extractConditionTree!((t, c) => treesAppA.put(tuple!(Tree, immutable(Formula)*)(t, c)))(treeA,
            childConditions[0], logicSystem);
    extractConditionTree!((t, c) => treesAppB.put(tuple!(Tree, immutable(Formula)*)(t, c)))(treeB,
            childConditions[1], logicSystem);

    outer: foreach (iB, ref treeTupleB2; treesAppB.data[treesAppBStartSize .. $])
    {
        auto treeB2 = treeTupleB2[0];
        foreach (iA, ref treeTupleA2; treesAppA.data[treesAppAStartSize .. $])
        {
            auto treeA2 = treeTupleA2[0];
            if (treeA2.nodeType.among(NodeType.nonterminal, NodeType.merged)
                    && treeB2.nodeType.among(NodeType.nonterminal,
                        NodeType.merged) && equalTrees(treeA2, treeB2))
            {
                treesAppA.data[treesAppAStartSize .. $][iA][1] = logicSystem.simplify(
                        logicSystem.distributeOrSimple(treesAppA.data[treesAppAStartSize .. $][iA][1],
                        treeTupleB2[1]));
                continue outer;
            }
            else if (treeA2.nodeType == NodeType.token
                    && treeB2.nodeType == NodeType.token && equalTrees(treeA2, treeB2))
            {
                treesAppA.data[treesAppAStartSize .. $][iA][1] = logicSystem.simplify(
                        logicSystem.distributeOrSimple(treesAppA.data[treesAppAStartSize .. $][iA][1],
                        treeTupleB2[1]));
                continue outer;
            }
        }

        foreach (iA, ref treeTupleA2; treesAppA.data[treesAppAStartSize .. $])
        {
            auto treeA2 = treeTupleA2[0];
            if (treeA2.nodeType == NodeType.merged && treeA2.name == treeB2.name
                    && treeA2.childs.length == treeB2.childs.length)
            {
                bool allCompatible = true;
                foreach (i; 0 .. treeA2.childs.length)
                {
                    if (!areTreesCompatible(treeA2.childs[i], treeB2.childs[i]))
                        allCompatible = false;
                }
                if (!allCompatible)
                    continue;
                Tree[] newChilds = new Tree[treeA2.childs.length];
                foreach (i; 0 .. treeA2.childs.length)
                {
                    newChilds[i] = mergeCompatibleTrees(treeA2.childs[i], treeB2.childs[i], childConditions,
                            logicSystem, anyErrorCondition, contextCondition, flags, indentNum);
                    if (!newChilds[i].isValid)
                    {
                        allCompatible = false;
                        break;
                    }
                }
                if (!allCompatible)
                    continue;
                Location nonterminalStart = minLoc(treeA2.start, treeB2.start);
                Location nonterminalEnd = maxLoc(treeA2.end, treeB2.end);

                Tree tree2;
                tree2 = Tree(treeA2.name, treeA2.nonterminalID,
                        treeA2.productionID, treeA2.nodeType, newChilds, treeAllocator);
                tree2.grammarInfo = treeA2.grammarInfo;
                tree2.setStartEnd(nonterminalStart, nonterminalEnd);
                treesAppA.data[treesAppAStartSize .. $][iA][0] = tree2;
                treesAppA.data[treesAppAStartSize .. $][iA][1] = logicSystem.simplify(
                        logicSystem.or(treesAppA.data[treesAppAStartSize .. $][iA][1],
                        treeTupleB2[1]));
                continue outer;
            }
            else if (areTreesCompatible(treeA2, treeB2))
            {
                Tree tree2 = mergeCompatibleTrees(treeA2, treeB2, childConditions,
                        logicSystem, anyErrorCondition, contextCondition, flags, indentNum);
                if (!tree2.isValid)
                    continue;
                treesAppA.data[treesAppAStartSize .. $][iA][0] = tree2;
                treesAppA.data[treesAppAStartSize .. $][iA][1] = logicSystem.simplify(
                        logicSystem.or(treesAppA.data[treesAppAStartSize .. $][iA][1],
                        treeTupleB2[1]));
                continue outer;
            }
        }
        foreach (iA, ref treeTupleA2; treesAppA.data[treesAppAStartSize .. $])
        {
            auto treeA2 = treeTupleA2[0];
            if (treeA2.isValid && treeB2.isValid /*&& treeA2.nonterminalID == treeB2.nonterminalID
                && treeA2.productionID == treeB2.productionID
                && treeA2.name == treeB2.name*/
                 && (treeA2.nodeType == NodeType.array || treeB2.nodeType == NodeType.array))
            {
                Location nonterminalStart = minLoc(treeA2.start, treeB2.start);
                Location nonterminalEnd = maxLoc(treeA2.end, treeB2.end);

                Tree[] childsA;
                if (treeA2.nodeType == NodeType.array)
                    childsA = treeA2.childs;
                else
                    childsA = [treeA2];

                Tree[] childsB;
                if (treeB2.nodeType == NodeType.array)
                    childsB = treeB2.childs;
                else
                    childsB = [treeB2];

                auto newContextCondition = logicSystem.and(contextCondition,
                        logicSystem.or(treeTupleA2[1], treeTupleB2[1]));

                Tree[] newChilds = mergeArrays(childsA, childsB, [
                    treeTupleA2[1], treeTupleB2[1]
                ], logicSystem, anyErrorCondition, newContextCondition,
                        flags & MergeFlags.recursiveFlags, indentNum + 4);

                treesAppA.data[treesAppAStartSize .. $][iA][0] = createArrayTree(newChilds);
                treesAppA.data[treesAppAStartSize .. $][iA][1] = logicSystem.simplify(
                        logicSystem.or(treesAppA.data[treesAppAStartSize .. $][iA][1],
                        treeTupleB2[1]));
                continue outer;
            }
        }

        treesAppA.put(Tuple!(Tree, immutable(Formula)*)(treeB2, treeTupleB2[1]));
    }
    if (treesAppA.data[treesAppAStartSize .. $].length == 1)
    {
        return treesAppA.data[treesAppAStartSize .. $][0][0];
    }

    if ((flags & (MergeFlags.nullOnTreeCondition | MergeFlags.nullOnTreeConditionRec)) != 0)
    {
        return Tree.init;
    }

    Tree[] treesOut;
    immutable(Formula)*[] conditionsOut;
    treesOut.length = treesAppA.data[treesAppAStartSize .. $].length;
    conditionsOut.length = treesAppA.data[treesAppAStartSize .. $].length;
    foreach (i; 0 .. treesAppA.data[treesAppAStartSize .. $].length)
    {
        treesOut[i] = treesAppA.data[treesAppAStartSize .. $][i][0];
        conditionsOut[i] = treesAppA.data[treesAppAStartSize .. $][i][1];
    }

    foreach (ref c; conditionsOut)
        c = logicSystem.removeRedundant(c, contextCondition);
    auto tree3 = new ConditionTreeStruct(treesOut, conditionsOut, "#PPIf");

    return tree3.toTree;
}

bool treesOverlapping(Tree t1, Tree t2)
{
    return (t1.end > t2.start && t1.start < t2.end) || (t2.end > t1.start && t2.start < t1.end);
}

bool equalTrees(CppParseTree treeA, CppParseTree treeB)
{
    if (treeA is treeB)
        return true;
    if (!treeA.isValid || !treeB.isValid)
        return false;
    if (treeA.nodeType != treeB.nodeType)
        return false;
    if (treeA.nodeType != NodeType.token && treeA.name != treeB.name)
        return false;
    if (treeA.nodeType == NodeType.token && treeA.content != treeB.content)
        return false;
    if (treeA.nonterminalID != treeB.nonterminalID)
        return false;
    if (treeA.productionID != treeB.productionID)
        return false;
    if (treeA.childs.length != treeB.childs.length)
        return false;
    if (treeA.nodeType == NodeType.token)
        if (treeA.start != treeB.start)
            return false;
    if ((treeA.nonterminalID == CONDITION_TREE_NONTERMINAL_ID) != (
            treeB.nonterminalID == CONDITION_TREE_NONTERMINAL_ID))
        return false;
    if (treeA.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        ConditionTree ctreeA = treeA.toConditionTree;
        ConditionTree ctreeB = treeB.toConditionTree;
        if (ctreeA.conditions.length != ctreeB.conditions.length)
            return false;
        foreach (i; 0 .. ctreeA.conditions.length)
        {
            if (ctreeA.conditions[i]!is ctreeB.conditions[i])
                return false;
        }
    }
    foreach (i; 0 .. treeA.childs.length)
        if (!equalTrees(treeA.childs[i], treeB.childs[i]))
            return false;
    return true;
}

Tree createArrayTree(Tree[] arrA)
{
    Location start = Location.invalid;
    Location end = Location.invalid;
    foreach (i, arr; arrA)
    {
        start = minLoc(start, arr.start);
        end = maxLoc(end, arr.end);
    }

    Tree a = Tree("[]", SymbolID.max, ProductionID.max, NodeType.array, arrA, treeAllocator);
    a.setStartEnd(start, end);

    return a;
}

Tree createArrayTreeSimple(Tree[] arrA)
{
    if (arrA.length == 1)
        return arrA[0];
    return createArrayTree(arrA);
}

ConditionTree createConditionTree(Tree[] arrA, Tree[] arrB, immutable(Formula)*[2] childConditions)
{
    Tree a = createArrayTree(arrA);
    Tree b = createArrayTree(arrB);

    auto r = new ConditionTreeStruct([a, b], childConditions.dup, "#PPIf");
    r.base.location.setStartEnd(minLoc(a.start, b.start), maxLoc(a.end, b.end));
    return r;
}

ConditionTree createConditionTree(Tree[] arrs, immutable(Formula)*[] conditions)
{
    Location start = Location.invalid;
    Location end = Location.invalid;
    foreach (i, arr; arrs)
    {
        start = minLoc(start, arr.start);
        end = maxLoc(end, arr.end);
    }

    auto r = new ConditionTreeStruct(arrs, conditions, "#PPIf");
    r.base.location.setStartEnd(start, end);
    return r;
}

void extractConditionTree(alias onTree)(CppParseTree tree, immutable(Formula)* condition,
        LogicSystem logicSystem, bool allowArrays = false, bool splitArrays = false)
{
    void visitTree(CppParseTree tree, immutable(Formula)* condition, size_t depth)
    {
        if (!tree.isValid)
        {
        }
        else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            ConditionTree ctree = tree.toConditionTree;
            foreach (i; 0 .. ctree.conditions.length)
            {
                visitTree(ctree.childs[i],
                        logicSystem.simplify(logicSystem.and(ctree.conditions[i],
                            condition)), depth + 1);
            }
        }
        else if (allowArrays /*depth > 0*/  && tree.nodeType == NodeType.array
                && tree.childs.length == 1)
        {
            visitTree(tree.childs[0], condition, depth + 1);
        }
        else if (splitArrays /*depth > 0*/  && tree.nodeType == NodeType.array)
        {
            foreach (c; tree.childs)
                visitTree(c, condition, depth + 1);
        }
        else
        {
            onTree(tree, condition);
        }
    }

    visitTree(tree, condition, 0);
}

class FileInstanceInfo
{
    immutable(LocationContext*)[] instanceLocations;
    immutable(Formula*)[] instanceConditions;
    immutable(Formula*)[] instanceConditionsUsed;
    LocConditions*[] instanceLocConditions;
    immutable(Formula)* usedCondition;
    bool badInclude;
}

immutable(LocationContext)* removeLocationPrefix(immutable(LocationContext)* lc,
        immutable(LocationContext)* prefix, LocationContextMap locationContextMap)
{
    size_t prefixDepth = 0;
    if (prefix !is null)
        prefixDepth = prefix.contextDepth;

    if (lc is null)
        return null;
    assert(lc.contextDepth >= prefixDepth);

    if (lc.contextDepth == prefixDepth)
    {
        assert(lc is prefix);
        return null;
    }
    auto c = removeLocationPrefix(lc.prev, prefix, locationContextMap);
    if (c is null)
        return locationContextMap.getLocationContext(immutable(LocationContext)(c, LocationN(),
                LocationN.LocationDiff(), lc.name, lc.filename, lc.isPreprocLocation));
    else
        return locationContextMap.getLocationContext(immutable(LocationContext)(c,
                lc.startInPrev, lc.lengthInPrev, lc.name, lc.filename, lc.isPreprocLocation));
}

LocationX removeLocationPrefix(LocationX l, immutable(LocationContext)* prefix,
        LocationContextMap locationContextMap)
{
    return LocationX(l.loc, removeLocationPrefix(l.context, prefix, locationContextMap));
}

Tree removeLocationPrefix(Tree tree, immutable(LocationContext)* prefix,
        LocationContextMap locationContextMap, immutable(Formula)* contextCondition, LogicSystem logicSystem,
        FileInstanceInfo[RealFilename] fileInstanceInfos,
        immutable(LocationContext)** lastLocContext)
{
    Tree visitTree(Tree tree, immutable(LocationContext)** lastLocContext)
    {
        if (!tree.isValid)
            return Tree.init;
        size_t prefixDepth = 0;
        if (prefix !is null)
            prefixDepth = prefix.contextDepth;
        assert(tree.start.context is null || tree.start.context.contextDepth >= prefixDepth,
                text(locationStr(tree.start), "  ", locationStr(LocationX(LocationN(), prefix))));
        immutable(LocationContext)* lc = tree.start.context;
        immutable(LocationContext)* lcEnd = tree.end.context;
        if (lc !is null)
        {
            lc = removeLocationPrefix(lc, prefix, locationContextMap);
            assert(lc !is null);
        }
        if (lcEnd !is null)
        {
            lcEnd = removeLocationPrefix(lcEnd, prefix, locationContextMap);
            assert(lcEnd !is null);
        }

        immutable(LocationContext)* lcNoMacros = lc;
        while (lcNoMacros !is null && lcNoMacros.name.length)
            lcNoMacros = lcNoMacros.prev;

        immutable(LocationContext)* lcGoodInclude = lcNoMacros;

        while (lcGoodInclude !is null && (RealFilename(lcGoodInclude.filename) !in fileInstanceInfos
                || fileInstanceInfos[RealFilename(lcGoodInclude.filename)].badInclude))
        {
            lcGoodInclude = lcGoodInclude.prev;
        }

        if (lcGoodInclude !is null && lcGoodInclude.contextDepth > 1)
        {
            LocationRangeX locRange;
            locRange.setStartEnd(LocationX(tree.start.loc, lc), LocationX(tree.end.loc, lcEnd));
            LocationRangeX locRangeReal = tree.location;

            LocationRangeX locRangeTmp = locRange;
            while (locRangeTmp.context.contextDepth > 2)
            {
                locRangeTmp = locRangeTmp.context.parentLocation;
                if (locRangeTmp.context.filename.length
                        && !fileInstanceInfos[RealFilename(locRangeTmp.context.filename)]
                            .badInclude)
                    locRange = locRangeTmp;
            }

            if (lastLocContext !is null)
            {
                if (locRange.context is *lastLocContext)
                    return Tree.init;
                *lastLocContext = locRange.context;
            }

            while (locRangeReal.context.contextDepth > ((prefix is null)
                    ? 0 : prefix.contextDepth) + locRange.context.contextDepth)
                locRangeReal = locRangeReal.context.parentLocation;

            string newText = locRange.context.filename;

            auto fileInstanceInfo = fileInstanceInfos[RealFilename(locRange.context.filename)];

            immutable(Formula)* instanceCondition;
            foreach (i, l; fileInstanceInfo.instanceLocations)
            {
                if (l is locRangeReal.context)
                {
                    instanceCondition = fileInstanceInfo.instanceConditions[i];
                    break;
                }
            }

            locRange = locRange.context.parentLocation;

            Tree newToken = Tree(newText, SymbolID.max, ProductionID.max,
                    NodeType.token, [], treeAllocator);
            newToken.setStartEnd(locRange.start, locRange.end);
            Tree newTree = Tree /*treeAllocator.allocate*/ ("@#IncludeDecl",
                    INCLUDE_TREE_NONTERMINAL_ID, INCLUDE_TREE_PRODUCTION_ID,
                    NodeType.nonterminal, [newToken]);
            newTree.setStartEnd(locRange.start, locRange.end);
            newTree.grammarInfo = &includeTreeGrammarInfo;

            if (instanceCondition !is null && !logicSystem.and(contextCondition,
                    instanceCondition.negated).isFalse)
            {
                instanceCondition = logicSystem.removeRedundant(instanceCondition,
                        contextCondition);
                auto instanceConditionNeg = logicSystem.removeRedundant(logicSystem.and(contextCondition,
                        instanceCondition.negated), contextCondition);
                return createConditionTree([newTree], [], [
                    instanceCondition, instanceConditionNeg
                ]).toTree;
            }

            return newTree;
        }

        Tree[] newChilds;
        if (tree.nodeType == NodeType.array)
        {
            newChilds.reserve(tree.childs.length);

            immutable(LocationContext)* lastLocContext2;

            foreach (c; tree.childs)
            {
                auto c2 = visitTree(c, &lastLocContext2);
                if (!c2.isValid)
                    continue;
                newChilds ~= c2;
            }
        }
        else
        {
            newChilds.length = tree.childs.length;

            foreach (i; 0 .. tree.childs.length)
                newChilds[i] = visitTree(tree.childs[i], null);
        }

        if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            ConditionTree ctree = tree.toConditionTree;
            immutable(Formula)*[] newConditions;
            newConditions.length = ctree.conditions.length;
            foreach (i; 0 .. newConditions.length)
            {
                newConditions[i] = logicSystem.removeRedundant(ctree.conditions[i],
                        contextCondition);
            }
            auto tree2 = new ConditionTreeStruct(newChilds, newConditions, tree.name);
            tree2.base.location.setStartEnd(LocationX(tree.start.loc, lc),
                    LocationX(tree.end.loc, lcEnd));
            return tree2.toTree;
        }
        else
        {
            Tree tree2 = Tree(tree.nameOrContent, tree.nonterminalID,
                    tree.productionID, tree.nodeType, newChilds, treeAllocator);
            tree2.grammarInfo = tree.grammarInfo;
            tree2.setStartEnd(LocationX(tree.start.loc, lc), LocationX(tree.end.loc, lcEnd));

            return tree2;
        }
    }

    return visitTree(tree, lastLocContext);
}

immutable(LocationContext)* getLocationFilePrefix(LocationX l)
{
    immutable(LocationContext)* prefix = l.context;
    while (prefix !is null && prefix.name.length)
        prefix = prefix.prev;
    return prefix;
}

LocationX removeLocationFilePrefix(LocationX l, LocationContextMap locationContextMap)
{
    immutable(LocationContext)* prefix = getLocationFilePrefix(l);
    if (prefix !is null)
        prefix = prefix.prev;
    return LocationX(l.loc, removeLocationPrefix(l.context, prefix, locationContextMap));
}
