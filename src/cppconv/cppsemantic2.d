
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppsemantic2;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppparserwrapper;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.runcppcommon;
import cppconv.treematching;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import std.algorithm;
import std.exception;
import std.stdio;
import std.traits;
import std.typetuple;

alias TypedefType = cppconv.cppsemantic.TypedefType;

void distributeExpectedType(Semantic semantic, Tree tree, QualType expectedType,
        immutable(Formula)* condition, bool preventStringToPointer = false)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
            distributeExpectedType(semantic, c, expectedType, condition, preventStringToPointer);
        return;
    }
    if (tree.nodeType != NodeType.nonterminal && tree.nodeType != NodeType.merged)
        return;
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            distributeExpectedType(semantic, ctree.childs[i], expectedType,
                    semantic.logicSystem.and(subTreeCondition, condition), preventStringToPointer);
        }
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        foreach (i; 0 .. tree.childs.length)
        {
            auto subTreeCondition = mdata.conditions[i];

            distributeExpectedType(semantic, tree.childs[i], expectedType,
                    semantic.logicSystem.and(subTreeCondition, condition), preventStringToPointer);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"BraceOrEqualInitializer")
    {
        distributeExpectedType(semantic, tree.childs[1], expectedType,
                condition, preventStringToPointer);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitializerClause"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitializerClauseDesignator")
    {
        distributeExpectedType(semantic, tree.childs[0], expectedType,
                condition, preventStringToPointer);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ConditionalExpression")
    {
        // LogicalOrExpression "?" Expression ":" AssignmentExpression
        distributeExpectedType(semantic, tree.childs[2], expectedType,
                condition, preventStringToPointer);
        distributeExpectedType(semantic, tree.childs[4], expectedType,
                condition, preventStringToPointer);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PrimaryExpression"
            && tree.childs.length == 3)
    {
        assert(tree.childs[0].content == "(");
        assert(tree.childs[2].content == ")");
        distributeExpectedType(semantic, tree.childs[1], expectedType,
                condition, preventStringToPointer);
    }
    else
    {
        semantic.extraInfo2(tree).preventStringToPointer |= preventStringToPointer;

        expectedType = filterType(expectedType, condition, semantic);

        if (semantic.extraInfo2(tree).convertedType.type is null)
            semantic.extraInfo2(tree).convertedType = expectedType;
        else
            semantic.extraInfo2(tree).convertedType = combineTypes(semantic.extraInfo2(tree)
                    .convertedType, expectedType, null, condition, semantic);
    }
}

void distributeAccessSpecifiers(ref ConditionMap!(AccessSpecifier) accessSpecifier,
        Tree tree, immutable(Formula)* condition, Semantic semantic)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
            distributeAccessSpecifiers(accessSpecifier, c, condition, semantic);
        return;
    }
    if (tree.nodeType != NodeType.nonterminal && tree.nodeType != NodeType.merged)
        return;
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            distributeAccessSpecifiers(accessSpecifier, ctree.childs[i],
                    semantic.logicSystem.and(subTreeCondition, condition), semantic);
        }
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        foreach (i; 0 .. tree.childs.length)
        {
            auto subTreeCondition = mdata.conditions[i];

            distributeAccessSpecifiers(accessSpecifier, tree.childs[i],
                    semantic.logicSystem.and(subTreeCondition, condition), semantic);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"AccessSpecifierWithColon")
    {
        AccessSpecifier s;
        enforce(tree.childs[0].nonterminalID == nonterminalIDFor!"AccessSpecifier");
        if (tree.childs[0].childs[0].content == "public")
            s = AccessSpecifier.public_;
        else if (tree.childs[0].childs[0].content == "private")
            s = AccessSpecifier.private_;
        else if (tree.childs[0].childs[0].content == "protected")
            s = AccessSpecifier.protected_;
        else
            enforce(false);
        if (tree.childs.length == 3 && tree.childs[1].isValid)
        {
            enforce(tree.childs[1].nodeType == NodeType.array);
            foreach (c; tree.childs[1].childs)
            {
                enforce(c.nonterminalID == nonterminalIDFor!"AccessSpecifierAnnotation");
                if (c.childs[0].content == "__cppconv_qt_slot")
                    s |= AccessSpecifier.qtSlot;
                else if (c.childs[0].content == "__cppconv_qt_signal")
                    s |= AccessSpecifier.qtSignal;
                else
                    enforce(false);
            }
        }
        accessSpecifier.addReplace(condition, s, semantic.logicSystem);
    }
    else
    {
        foreach (e; accessSpecifier.entries)
            semantic.extraInfo2(tree).accessSpecifier.add(semantic.logicSystem.and(e.condition,
                    condition), e.data, semantic.logicSystem);
    }
}

void analyzeDeclSpecifierSeq2(Tree tree, immutable(Formula)* condition,
        Semantic semantic, ref ConditionMap!AccessSpecifier accessSpecifier)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (i; 0 .. tree.childs.length)
        {
            analyzeDeclSpecifierSeq2(tree.childs[i], condition, semantic, accessSpecifier);
        }
    }
    else if (tree.nodeType == NodeType.nonterminal && tree.nodeType == NodeType.merged
            && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            analyzeDeclSpecifierSeq2(ctree.childs[i],
                    semantic.logicSystem.and(subTreeCondition, condition),
                    semantic, accessSpecifier);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclSpecifierSeq")
    {
        foreach (i; 0 .. tree.childs.length)
        {
            analyzeDeclSpecifierSeq2(tree.childs[i], condition, semantic, accessSpecifier);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"AttributeSpecifier")
    {
        if (tree.childs[0].content == "__cppconv_qt_slot")
            accessSpecifier.addBitOr(condition, AccessSpecifier.qtSlot, semantic.logicSystem);
        if (tree.childs[0].content == "__cppconv_qt_signal")
            accessSpecifier.addBitOr(condition, AccessSpecifier.qtSignal, semantic.logicSystem);
        if (tree.childs[0].content == "__cppconv_qt_invokable")
            accessSpecifier.addBitOr(condition, AccessSpecifier.qtInvokable, semantic.logicSystem);
        if (tree.childs[0].content == "__cppconv_qt_scriptable")
            accessSpecifier.addBitOr(condition, AccessSpecifier.qtScriptable,
                    semantic.logicSystem);
    }
}

void runSemantic2(Semantic semantic, ref Tree tree, Tree parent, immutable(Formula)* condition)
{
    if (!tree.isValid)
        return;

    if (condition.isFalse)
        return;

    // runSemantic should visit every subtree at most once
    assert(tree !in semantic.treesVisited, tree.start.locationStr);
    semantic.treesVisited[tree] = true;

    auto extraInfoHere = &semantic.extraInfo(tree);
    auto extraInfoHere2 = &semantic.extraInfo2(tree);

    if (tree.nodeType == NodeType.token)
    {
        return;
    }
    else if (tree.nodeType != NodeType.nonterminal && tree.nodeType != NodeType.merged)
    {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
        return;
    }

    Tree realParent = getRealParent(tree, semantic);

    assert((tree.nonterminalID >= 30_000) == (tree.name.startsWith("Merged")));
    assert((tree.nonterminalID >= 30_000) == (tree.nodeType == NodeType.merged));

    if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        QualType combinedType;
        foreach (i; 0 .. tree.childs.length)
        {
            auto subTreeCondition = mdata.conditions[i];

            auto condition2 = semantic.logicSystem.and(condition, subTreeCondition);

            runSemantic2(semantic, tree.childs[i], tree, condition2);

            foreach (e; semantic.extraInfo2(tree.childs[i]).constantValue.entries)
            {
                extraInfoHere2.constantValue.add(condition2, e.data, semantic.logicSystem);
            }
        }

        return;
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        QualType combinedType;
        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            runSemantic2(semantic, ctree.childs[i], tree,
                    semantic.logicSystem.and(subTreeCondition, condition));

            foreach (e; semantic.extraInfo2(ctree.childs[i]).constantValue.entries)
            {
                extraInfoHere2.constantValue.add(semantic.logicSystem.and(e.condition,
                        subTreeCondition), e.data, semantic.logicSystem);
            }
        }

        return;
    }

    alias Funcs = AliasSeq!((MatchNonterminals!("SimpleDeclaration*",
            "MemberDeclaration*", "FunctionDefinitionMember",
            "FunctionDefinitionGlobal", "ParameterDeclaration",
            "ParameterDeclarationAbstract", "Condition")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
        if (tree.hasChildWithName("declSeq"))
        {
            analyzeDeclSpecifierSeq2(tree.childByName("declSeq"), condition,
                semantic, semantic.extraInfo2(tree).accessSpecifier);
        }
        else if (tree.childs[0].nonterminalID == nonterminalIDFor!"FunctionDefinitionHead")
        {
            analyzeDeclSpecifierSeq2(tree.childs[0].childByName("declSeq"),
                condition, semantic, semantic.extraInfo2(tree).accessSpecifier);
        }
    }, (MatchNonterminals!("*Declarator"), MatchRealParentNonterminals!("SimpleDeclaration*", "MemberDeclaration*",
            "FunctionDefinitionHead", "ParameterDeclaration",
            "ParameterDeclarationAbstract", "Condition")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
        if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitDeclarator")
            distributeExpectedType(semantic, tree.childs[1],
                semantic.extraInfo(tree).type, condition);
    }, (MatchNonterminals!("ClassSpecifier", "ElaboratedTypeSpecifier", "EnumSpecifier", "TypeParameter")) {
        bool isTemplateSpecializationHere;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            if (iteratePPVersions!isTemplateSpecialization(tree, ppVersion))
            {
                isTemplateSpecializationHere = true;
                continue;
            }
        }

        if (isTemplateSpecializationHere)
            return;

        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("Enumerator")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("FunctionBody")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("MemInitializer")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            Tree treeMember = ppVersion.chooseTree(tree.childs[0]);
            Tree treeMember2 = ppVersion.chooseTree(treeMember.childs[$ - 1]);
            if (treeMember2.name != "NameIdentifier")
                continue;
            DeclarationSet ds;
            foreach (e; semantic.extraInfo(treeMember2).referenced.entries)
            {
                if (isInCorrectVersion(ppVersion, e.condition))
                    ds = e.data;
            }
            if (ds is null)
                continue;

            Tree treeCtorInitializer = getRealParent(tree, semantic);
            assert(treeCtorInitializer.isValid
                && treeCtorInitializer.nonterminalID == nonterminalIDFor!"CtorInitializer");
            Tree treeFunctionBody = getRealParent(treeCtorInitializer, semantic);
            assert(treeFunctionBody.isValid
                && treeFunctionBody.nonterminalID == nonterminalIDFor!"FunctionBody");
            Tree treeFunctionDefinition = getRealParent(treeFunctionBody, semantic);
            assert(treeFunctionDefinition.isValid
                && treeFunctionDefinition.name.startsWith("FunctionDefinition"));

            Declaration functionDeclaration;
            foreach (d; semantic.extraInfo(treeFunctionDefinition).declarations)
            {
                if (!d.name.startsWith("$norettype:"))
                    continue;
                if (isInCorrectVersion(ppVersion, d.condition))
                {
                    assert(functionDeclaration is null);
                    functionDeclaration = d;
                }
            }
            if (functionDeclaration is null)
                continue;
            Scope classScope = functionDeclaration.scope_;
            if (functionDeclaration.tree !in functionDeclaration.scope_.childScopeByTree)
                continue;
            Scope functionScope = functionDeclaration.scope_
                .childScopeByTree[functionDeclaration.tree];
            foreach (e; functionScope.extraParentScopes.entries)
            {
                if (e.data.type == ExtraScopeType.namespace
                    && isInCorrectVersion(ppVersion, e.condition))
                    classScope = e.data.scope_;
            }
            if (ds.scope_ !is classScope)
                continue;
            QualType functionTypeX = chooseType(functionDeclaration.type2, ppVersion, true);
            if (functionTypeX.kind != TypeKind.function_)
                continue;
            FunctionType functionType = cast(FunctionType) functionTypeX.type;
            if (functionType.parameters.length)
                continue;

            foreach (e; ds.entries)
                semantic.declarationExtra2(e.data).defaultInit.add(semantic.logicSystem.and(ppVersion.condition,
                    e.condition), tree, semantic.logicSystem);
        }

        if (tree.childs.length == 2)
        {
            distributeExpectedType(semantic, tree.childs[1],
                semantic.extraInfo(tree.childs[0]).type, condition);
        }
    }, (MatchNonterminals!("ClassBody")) {
        ConditionMap!(AccessSpecifier) accessSpecifier;
        distributeAccessSpecifiers(accessSpecifier, tree.childs[1], condition, semantic);

        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            Declaration[] declarations;
            collectRecordFields(tree.childs[1], ppVersion.condition, semantic,
                ppVersion, declarations);

            BitFieldInfo bitFieldInfo;

            foreach (i, d; declarations)
            {
                if (d.bitfieldSize > 0)
                {
                    if (bitFieldInfo.dataName.length == 0)
                    {
                        bitFieldInfo.dataName = "bitfieldData_" ~ d.name;

                        size_t wholeLength;
                        foreach (d2; declarations[i .. $])
                        {
                            if (d2.bitfieldSize == 0)
                                break;
                            wholeLength += d2.bitfieldSize;
                        }

                        bitFieldInfo.wholeLength = wholeLength;
                    }
                    bitFieldInfo.length = d.bitfieldSize;

                    d.bitFieldInfo.add(ppVersion.condition, bitFieldInfo, semantic.logicSystem);

                    bitFieldInfo.firstBit += d.bitfieldSize;
                }
                else
                {
                    bitFieldInfo = BitFieldInfo.init;
                }
            }
        }
    }, (MatchNonterminals!("NameIdentifier"), MatchRealParentNonterminals!("*Expression",
            "BraceOrEqualInitializer", "BracedInitList", "DeclSpecifierSeq",
            "EnumeratorInitializer",
            "ArrayDeclarator", "JumpStatement2", "LabelStatement",
            "SelectionStatement", "IterationStatement", "DoWhileStatement")) {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].isToken == 1);
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        bool acessingBitField;

        foreach (e; extraInfoHere.referenced.entries)
        {
            foreach (e2; e.data.entries)
            {
                if (semantic.logicSystem.and(e.condition, e2.condition).isFalse)
                    continue;
                if (e2.data.bitfieldSize > 0)
                    acessingBitField = true;
            }
        }

        extraInfoHere2.acessingBitField |= acessingBitField;
    }, (MatchNonterminals!("InitializerClause")) {
        if (realParent.isValid && realParent.nonterminalID == nonterminalIDFor!"BracedInitList")
            distributeExpectedType(semantic, tree.childs[0], extraInfoHere.type,
                condition, realParent.nonterminalID == nonterminalIDFor!"BracedInitList");
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("InitializerClauseDesignator")) {
        if (realParent.nonterminalID == nonterminalIDFor!"BracedInitList")
            distributeExpectedType(semantic, tree.childs[$ - 1], extraInfoHere.type,
                condition, realParent.nonterminalID == nonterminalIDFor!"BracedInitList");
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1] == q{"("} && !p.symbols[0].isToken)) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        QualType functionType = semantic.extraInfo(tree.childs[0]).type;

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            Tree[] parameterExprs;
            bool hasNonterminal;
            iteratePPVersions!collectParameterExprs(tree.childs[2], ppVersion,
                semantic, parameterExprs, hasNonterminal);

            QualType functionType2 = chooseType(functionType, ppVersion, true);
            if (functionType2.type !is null && functionType2.kind == TypeKind.pointer)
                functionType2 = (cast(PointerType) functionType2.type).next;

            QualType[] parameterTypes;
            if (functionType2.type !is null && functionType2.kind == TypeKind.function_)
                parameterTypes = (cast(FunctionType) functionType2.type).parameters;

            foreach (i; 0 .. parameterExprs.length)
            {
                if (i < parameterTypes.length && parameterTypes[i].type !is null)
                {
                    auto ptype = parameterTypes[i];
                    distributeExpectedType(semantic, parameterExprs[i],
                        ptype, ppVersion.condition);
                }
                else
                {
                    QualType ptype = semantic.extraInfo(parameterExprs[i]).type;
                    if (ptype.type !is null && ptype.kind == TypeKind.array)
                    {
                        auto atype = cast(ArrayType) ptype.type;
                        ptype = QualType(semantic.getPointerType(atype.next), ptype.qualifiers);
                    }
                    distributeExpectedType(semantic, parameterExprs[i], ptype,
                        ppVersion.condition, true);
                }
            }
        }
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1].among(q{"->"}, q{"."}))) {
        //   | PostfixExpression "." "template"? IdExpression

        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
        extraInfoHere2.acessingBitField |= semantic.extraInfo2(tree.childs[3]).acessingBitField;
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1] == q{"["} && symbolNames[3] == q{"]"})) {
        // PostfixExpression "[" Expression "]"
        // PostfixExpression "[" BracedInitList? "]" //C++0x

        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 2 && (symbolNames[1] == q{"++"} || symbolNames[1] == q{"--"}))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "PrimaryExpression" && symbolNames.length == 3)) {
        assert(tree.childs[0].content == "(");
        assert(tree.childs[2].content == ")");

        runSemantic2(semantic, tree.childs[1], tree, condition);
        foreach (e; semantic.extraInfo2(tree.childs[1]).constantValue.entries)
        {
            extraInfoHere2.constantValue.add(e.condition, e.data, semantic.logicSystem);
        }
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "ConditionalExpression")) {
        // LogicalOrExpression "?" Expression ":" AssignmentExpression

        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        QualType combinedType1;
        QualType combinedType2;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            auto type1 = chooseType(semantic.extraInfo(tree.childs[2]).type, ppVersion, true);
            auto type2 = chooseType(semantic.extraInfo(tree.childs[4]).type, ppVersion, true);

            if (type1.type !is null && type1.kind == TypeKind.array)
                type1 = QualType(semantic.getPointerType(type1.allNext()[0]), type1.qualifiers);
            if (type2.type !is null && type2.kind == TypeKind.array)
                type2 = QualType(semantic.getPointerType(type2.allNext()[0]), type2.qualifiers);

            combinedType1 = combineTypes(combinedType1, type1, null,
                ppVersion.condition, semantic);
            combinedType2 = combineTypes(combinedType2, type2, null,
                ppVersion.condition, semantic);
        }

        distributeExpectedType(semantic, tree.childs[2], combinedType1, condition);
        distributeExpectedType(semantic, tree.childs[4], combinedType2, condition);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "RelationalExpression")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        QualType combinedType1;
        QualType combinedType2;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            auto type1 = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);
            auto type2 = chooseType(semantic.extraInfo(tree.childs[2]).type, ppVersion, true);

            if (type1.type !is null && type1.kind == TypeKind.array)
                type1 = QualType(semantic.getPointerType(type1.allNext()[0]), type1.qualifiers);
            if (type2.type !is null && type2.kind == TypeKind.array)
                type2 = QualType(semantic.getPointerType(type2.allNext()[0]), type2.qualifiers);

            combinedType1 = combineTypes(combinedType1, type1, null,
                ppVersion.condition, semantic);
            combinedType2 = combineTypes(combinedType2, type2, null,
                ppVersion.condition, semantic);
        }

        distributeExpectedType(semantic, tree.childs[0], combinedType1, condition);
        distributeExpectedType(semantic, tree.childs[2], combinedType2, condition);
    }, (MatchNonterminals!("Literal")) {
        string value;
        assert(tree.childs[0].isToken, locationStr(tree.start));
        value = tree.childs[0].content;

        // https://en.cppreference.com/w/cpp/language/integer_literal

        while (value.length && value[$ - 1].inCharSet!"lLuU")
            value = value[0 .. $ - 1];
        ulong valueI = parseIntLiteral(value);
        extraInfoHere2.constantValue.add(condition, valueI, semantic.logicSystem);
    }, (MatchNonterminals!("FloatLiteral")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("CharLiteral")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("BooleanLiteral")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("PointerLiteral")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("StringLiteral2")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("StringLiteralSequence")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("LiteralS")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("CastExpression", "CompoundLiteralExpression")) {
        assert(tree.childs[0].content == "(");
        assert(tree.childs[2].content == ")");
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        QualType combinedType1;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            auto type = chooseType(semantic.extraInfo(tree).type, ppVersion, true);
            auto type1 = chooseType(semantic.extraInfo(tree.childs[3]).type, ppVersion, true);

            if (type1.type !is null && type1.kind == TypeKind.function_)
                type1 = QualType(semantic.getPointerType(type1));
            if (type1.type !is null && type1.kind == TypeKind.array && type.kind == TypeKind.pointer)
                type1 = QualType(semantic.getPointerType(type1.allNext()[0]), type1.qualifiers);

            combinedType1 = combineTypes(combinedType1, type1, null,
                ppVersion.condition, semantic);
        }

        distributeExpectedType(semantic, tree.childs[3], combinedType1, condition);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "sizeof" && tree.childs.length == 4))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        //distributeExpectedType(semantic, tree.childs[3], combinedType, condition);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "sizeof" && tree.childs.length == 2))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "__builtin_offsetof"))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "__builtin_va_arg"))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("-", "+", "~") && tree.childs.length == 2))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("&") && tree.childs.length == 2))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("*") && tree.childs.length == 2))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        QualType combinedType1;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            auto t = chooseType(semantic.extraInfo(tree.childs[1]).type, ppVersion, true);

            if (t.type !is null && t.kind == TypeKind.array)
                t = QualType(semantic.getPointerType(t.allNext()[0]), t.qualifiers);

            combinedType1 = combineTypes(combinedType1, t, null, ppVersion.condition, semantic);
        }
        distributeExpectedType(semantic, tree.childs[1], combinedType1, condition);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "JumpStatement2" && symbolNames[0] == q{"return"})) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        Tree funcDeclTree = getRealParent(tree, semantic);
        while (funcDeclTree.isValid && (funcDeclTree.name.endsWith("Statement")
            || funcDeclTree.nonterminalID.nonterminalIDAmong!("TryBlock", "Handler")))
            funcDeclTree = getRealParent(funcDeclTree, semantic);
        if (!funcDeclTree.isValid || funcDeclTree.name != "FunctionBody")
            return;
        assert(funcDeclTree.nonterminalID == nonterminalIDFor!"FunctionBody", funcDeclTree.name);
        funcDeclTree = getRealParent(funcDeclTree, semantic);
        assert(funcDeclTree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember", "FunctionDefinitionGlobal"));

        QualType combinedType;
        foreach (d; semantic.extraInfo(funcDeclTree).declarations)
        {
            auto type = functionResultType(d.type2, semantic);
            combinedType = combineTypes(combinedType, type, null, d.condition, semantic);
        }
        distributeExpectedType(semantic, tree.childs[1], combinedType, condition);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "SelectionStatement" && symbolNames[0] == q{"switch"})) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
        immutable(Formula)* afterStatement = semantic.logicSystem.false_;
        analyzeSwitch(semantic, tree.childs[$ - 1], condition, afterStatement);
        extraInfoHere2.labelNeedsGoto = afterStatement;
    }, (MatchNonterminals!("AssignmentExpression")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        if (tree.childs[1].childs[0].content == "=")
        {
            distributeExpectedType(semantic, tree.childs[2],
                semantic.extraInfo(tree.childs[0]).type, condition);
        }
        extraInfoHere2.acessingBitField |= semantic.extraInfo2(tree.childs[0]).acessingBitField;
    }, (MatchNonterminals!("EqualityExpression")) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        auto t1 = semantic.extraInfo(tree.childs[0]).type;
        auto t2 = semantic.extraInfo(tree.childs[2]).type;

        QualType combinedTypeLhs;
        QualType combinedTypeRhs;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            auto t1x = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);
            auto t2x = chooseType(semantic.extraInfo(tree.childs[2]).type, ppVersion, true);
            auto lhs = t1;
            auto rhs = t2;

            if (t1x.kind == TypeKind.array && t2x.kind == TypeKind.pointer)
                lhs = QualType(semantic.getPointerType((cast(ArrayType) t1x.type)
                    .next), t1x.qualifiers);
            if (t1x.kind == TypeKind.pointer && t2x.kind == TypeKind.array)
                rhs = QualType(semantic.getPointerType((cast(ArrayType) t2x.type)
                    .next), t2x.qualifiers);

            if (t1x.kind == TypeKind.function_ && t2x.kind == TypeKind.pointer)
                lhs = QualType(semantic.getPointerType(t1x), Qualifiers.none);
            if (t1x.kind == TypeKind.pointer && t2x.kind == TypeKind.function_)
                rhs = QualType(semantic.getPointerType(t2x), Qualifiers.none);

            if (t1x.kind == TypeKind.builtin && t2x.kind.among(TypeKind.pointer, TypeKind.array))
                lhs = t2;
            if (t1x.kind.among(TypeKind.pointer, TypeKind.array) && t2x.kind == TypeKind.builtin)
                rhs = t1;

            combinedTypeLhs = combineTypes(combinedTypeLhs, lhs, null,
                ppVersion.condition, semantic);
            combinedTypeRhs = combineTypes(combinedTypeRhs, rhs, null,
                ppVersion.condition, semantic);
        }
        distributeExpectedType(semantic, tree.childs[0], combinedTypeLhs, condition);
        distributeExpectedType(semantic, tree.childs[2], combinedTypeRhs, condition);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("MultiplicativeExpression", "AdditiveExpression",
            "AndExpression", "InclusiveOrExpression", "ExclusiveOrExpression", "AndExpression"))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }

        auto t1 = semantic.extraInfo(tree.childs[0]).type;
        auto t2 = semantic.extraInfo(tree.childs[2]).type;

        QualType combinedTypeLhs;
        QualType combinedTypeRhs;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            auto lhs = chooseType(t1, ppVersion, true);
            auto rhs = chooseType(t2, ppVersion, true);

            if (lhs.type !is null && lhs.kind == TypeKind.array)
                lhs = QualType(semantic.getPointerType((cast(ArrayType) lhs.type)
                    .next), lhs.qualifiers);
            if (rhs.type !is null && rhs.kind == TypeKind.array)
                rhs = QualType(semantic.getPointerType((cast(ArrayType) rhs.type)
                    .next), rhs.qualifiers);

            combinedTypeLhs = combineTypes(combinedTypeLhs, lhs, null,
                ppVersion.condition, semantic);
            combinedTypeRhs = combineTypes(combinedTypeRhs, rhs, null,
                ppVersion.condition, semantic);
        }
        distributeExpectedType(semantic, tree.childs[0], combinedTypeLhs, condition);
        distributeExpectedType(semantic, tree.childs[2], combinedTypeRhs, condition);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("ShiftExpression"))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("CompoundStatement"))) {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    }, (MatchProductionId!(INCLUDE_TREE_PRODUCTION_ID)) {
    }, () {
        foreach (ref c; tree.childs)
        {
            runSemantic2(semantic, c, tree, condition);
        }
    });

    mixin(generateMatchTreeCode!Funcs());
}
