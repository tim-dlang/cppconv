
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppsemantic1;
import core.time;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppparserwrapper;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.filecache;
import cppconv.mergedfile;
import cppconv.runcppcommon;
import cppconv.treematching;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.traits;
import std.typetuple;

alias TypedefType = cppconv.cppsemantic.TypedefType;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

Declaration selectParameterDeclaration(Tree tree, Semantic semantic, ref IteratePPVersions ppVersion)
{
    Declaration r;
    foreach (d; semantic.extraInfo(tree).declarations)
    {
        if (d.type == DeclarationType.type)
            continue;
        if (!isInCorrectVersion(ppVersion, d.condition))
            continue;
        assert(r is null);
        r = d;
    }
    return r;
}

Tree getFunctionDeclarator(Tree tree, ref IteratePPVersions ppVersion)
{
    while (true)
    {
        tree = ppVersion.chooseTree(tree);
        if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"FunctionDeclarator")
            return tree;
        if (tree.hasChildWithName("innerDeclarator"))
            tree = tree.childByName("innerDeclarator");
        else
            return Tree.init;
    }
}

void addFunctionParamReclDecls(Declaration d, Declaration d2,
        immutable(Formula)* condition, ref SemanticRunInfo semantic)
{
    if (d.scope_ is d2.scope_)
        return;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

        ParameterInfo parameterInfo;
        ParameterInfo parameterInfo2;

        auto declarator1 = getFunctionDeclarator(d.declaratorTree, ppVersion);
        auto declarator2 = getFunctionDeclarator(d2.declaratorTree, ppVersion);
        if (!declarator1.isValid || !declarator2.isValid)
            continue;

        iteratePPVersions!collectParameters(declarator1.childs[1], ppVersion,
                semantic, parameterInfo, false);
        iteratePPVersions!collectParameters(declarator2.childs[1], ppVersion,
                semantic, parameterInfo2, false);

        if (parameterInfo.parameters.length == 1 && chooseType(parameterInfo.parameters[0],
                ppVersion, false).type is semantic.getBuiltinType("void"))
        {
            parameterInfo.parameters = [];
            parameterInfo.parameterTrees = [];
        }
        if (parameterInfo2.parameters.length == 1
            && chooseType(parameterInfo2.parameters[0], ppVersion, false).type is semantic.getBuiltinType("void"))
        {
            parameterInfo2.parameters = [];
            parameterInfo2.parameterTrees = [];
        }
        if (parameterInfo.parameterTrees.length != parameterInfo2.parameterTrees.length)
        {
            continue;
        }
        enforce(parameterInfo.parameterTrees.length == parameterInfo2.parameterTrees.length,
                text(d.name, " ", locationStr(d.location), " ", d2.name, " ",
                    locationStr(d2.location), " ", parameterInfo.parameterTrees.length,
                    " ", parameterInfo2.parameterTrees.length));
        foreach (i; 0 .. parameterInfo.parameterTrees.length)
        {
            auto p1 = selectParameterDeclaration(parameterInfo.parameterTrees[i],
                    semantic, ppVersion);
            auto p2 = selectParameterDeclaration(parameterInfo2.parameterTrees[i],
                    semantic, ppVersion);
            if (p1 !is null && p2 !is null)
            {
                p2.realDeclaration.add(ppVersion.condition, p1, ppVersion.logicSystem);
            }
        }
    }
}

Declaration addOrUpdateDeclaration(DeclarationKey dk, Tree tree, immutable(Formula)* condition,
        bool outsideSymbolTable, Scope targetScope, Semantic semantic,
        bool allowName = true, immutable(Formula)** oldCondition = null)
{
    auto dkInCache = dk in semantic.declarationCache;
    Declaration d;
    if (dkInCache)
    {
        d = *dkInCache;

        if (oldCondition !is null)
            *oldCondition = d.condition;
        d.condition = semantic.logicSystem.or(d.condition, condition);
        if (dk.name.length && allowName)
        {
            targetScope.updateDeclarationCondition(dk.name, d.condition, d, semantic.logicSystem);
        }
    }
    else
    {
        d = new Declaration();
        d.condition = condition;
        semantic.declarationCache[dk] = d;
        d.key = dk;

        if (dk.name.length && allowName)
        {
            targetScope.addDeclaration(dk.name, condition, d, semantic.logicSystem);
        }
        else
        {
            auto ds = new DeclarationSet(dk.name, targetScope);
            ds.outsideSymbolTable = outsideSymbolTable;
            ds.addNew(d, semantic.logicSystem, true);
        }
        semantic.extraInfo(tree).declarations ~= d;
    }
    return d;
}

void runSemantic(ref SemanticRunInfo semantic, ref Tree tree, Tree parent,
        immutable(Formula)* condition)
{
    assert(semantic.rootScope.initialized);
    if (!tree.isValid)
        return;

    if (semantic.afterMerge)
        semantic.extraInfo(tree).sourceTrees++;

    if (condition.isFalse)
        return;

    // runSemantic should visit every subtree at most once
    assert(tree !in semantic.treesVisited, tree.start.locationStr);
    semantic.treesVisited[tree] = true;

    auto extraInfoHere = &semantic.extraInfo(tree);

    extraInfoHere.parent = parent;

    immutable(Formula)* instanceConditionHere = condition;
    if (semantic.instanceCondition !is null)
        instanceConditionHere = semantic.logicSystem.and(instanceConditionHere,
                semantic.instanceCondition);

    void updateType(ref QualType t, QualType t2)
    {
        t = t2;
    }

    if (tree.nodeType == NodeType.token)
    {
        return;
    }
    else if (tree.nodeType != NodeType.nonterminal && tree.nodeType != NodeType.merged)
    {
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
        return;
    }

    size_t indexInRealParent;
    Tree realParent = getRealParent(tree, semantic, &indexInRealParent);

    if (tree.nodeType == NodeType.merged && () {
            return (tree.name.endsWith("Expression")
                    && tree.name != "TypeIdOrExpression")
                || tree.name.endsWith("InitializerClause")
                || tree.name.endsWith("ArrayDeclarator")
                || tree.name.endsWith("TemplateArgument")
                || tree.name.endsWith("TemplateArgument2")
                || tree.name.endsWith("EnumeratorInitializer")
                || tree.name.endsWith("FunctionDefinitionHead")
                || tree.name.endsWith("StaticAssertDeclarationX")
                || tree.name.endsWith("Statement")
                || tree.nonterminalID == nonterminalIDFor!"TemplateArgumentList";
        }())
    {
        immutable(Formula)* goodConditionStrict = condition;
        immutable(Formula)* goodCondition = condition;
        handleConflictExpression(tree, goodConditionStrict, goodCondition,
                semantic, ConflictExpressionFlags.none);

        auto mdata = &semantic.mergedTreeData(tree);

        QualType combinedType;
        foreach (i; 0 .. tree.childs.length)
        {
            auto subTreeCondition = mdata.conditions[i];
            if (semantic.instanceCondition !is null)
                subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                        semantic.instanceCondition, semantic.logicSystem);

            auto condition2 = semantic.logicSystem.and(condition, subTreeCondition);
            semantic.extraInfo(tree.childs[i]).contextType = extraInfoHere.contextType;

            runSemantic(semantic, tree.childs[i], tree, condition2);
            combinedType = combineTypes(combinedType,
                    semantic.extraInfo(tree.childs[i]).type, null, condition2, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
        return;
    }
    else if (tree.nodeType == NodeType.merged && tree.childs.length == 2)
    {
        immutable(Formula)* conditionA = semantic.logicSystem.false_;
        immutable(Formula)* conditionB = semantic.logicSystem.false_;
        auto mdata = &semantic.mergedTreeData(tree);
        mdata.mergedCondition = semantic.logicSystem.or(mdata.mergedCondition, condition);

        immutable(Formula)* extraConditionA = semantic.logicSystem.true_;
        immutable(Formula)* extraConditionB = semantic.logicSystem.true_;
        Tree treeA = tree.childs[0];
        Tree treeB = tree.childs[1];
        bool swapped;
        if (treeA.nonterminalID == CONDITION_TREE_NONTERMINAL_ID && treeA.childs.length == 2 && !treeA.childs[1].isValid)
        {
            extraConditionA = treeA.toConditionTree.conditions[0];
            treeA = treeA.childs[0];
        }
        if (treeB.nonterminalID == CONDITION_TREE_NONTERMINAL_ID && treeB.childs.length == 2 && !treeB.childs[1].isValid)
        {
            extraConditionB = treeB.toConditionTree.conditions[0];
            treeB = treeB.childs[0];
        }

        bool handled;
        foreach (handler; AliasSeq!(handleConflictInitDeclarator, handleConflictTypeof,
                handleConflictMemberDeclaration, handleConflictConstructor,
                handleConflictTemplateParameter,))
        {
            if (__traits(getAttributes, handler)[0].check(tree, treeA, treeB))
            {
                assert(!handled);
                handled = true;
                handler(semantic, tree, treeA, treeB, conditionA, conditionB, condition);
            }
            else if (__traits(getAttributes, handler)[0].check(tree, treeB, treeA))
            {
                assert(!handled);
                handled = true;
                swapped = true;
                handler(semantic, tree, treeB, treeA, conditionB, conditionA, condition);
            }
        }

        if (handled)
        {
            with (semantic.logicSystem)
            {
                conditionA = and(conditionA, extraConditionA);
                conditionB = and(conditionB, extraConditionB);
                conditionA = or(conditionA, extraConditionB.negated);
                conditionB = or(conditionB, extraConditionA.negated);

                immutable(Formula)* conditionMerged = semantic.logicSystem.and(semantic.logicSystem.and(condition,
                        conditionA.negated), conditionB.negated);

                immutable(Formula)* conditionA2 = conditionA;
                immutable(Formula)* conditionB2 = conditionB;
                if (conditionMerged !is false_)
                {
                    conditionA2 = or(conditionA2, and(conditionMerged, literal("#merged")));
                    conditionB2 = or(conditionB2, and(conditionMerged, literal("#merged")));
                }

                mdata.conditions[0] = or(mdata.conditions[0], and(condition, conditionA));
                mdata.conditions[1] = or(mdata.conditions[1], and(condition, conditionB));
                mdata.mergedCondition = and(mdata.mergedCondition,
                        and(condition, or(conditionA, conditionB)).negated);

                if (swapped && conditionB2 !is false_)
                {
                    runSemantic(semantic, treeB, tree, and(condition, conditionB2));
                }
                if (conditionA2 !is false_)
                {
                    runSemantic(semantic, treeA, tree, and(condition, conditionA2));
                }
                if (!swapped && conditionB2 !is false_)
                {
                    runSemantic(semantic, treeB, tree, and(condition, conditionB2));
                }
            }
            return;
        }

        {
            foreach (ref c; tree.childs)
            {
                runSemantic(semantic, c, tree,
                        semantic.logicSystem.and(semantic.logicSystem.literal("#merged"),
                            condition));
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
            if (semantic.instanceCondition !is null)
                subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                        semantic.instanceCondition, semantic.logicSystem);

            semantic.extraInfo(ctree.childs[i]).contextType = extraInfoHere.contextType;

            runSemantic(semantic, ctree.childs[i], tree,
                    semantic.logicSystem.and(subTreeCondition, condition));
            combinedType = combineTypes(combinedType, semantic.extraInfo(ctree.childs[i])
                    .type, null, semantic.logicSystem.and(ctree.conditions[i],
                        condition), semantic);
        }

        updateType(extraInfoHere.type, combinedType);
        return;
    }

    alias Funcs = AliasSeq!((MatchNonterminals!("SimpleDeclaration*",
            "MemberDeclaration*", "FunctionDefinitionMember",
            "FunctionDefinitionGlobal", "ParameterDeclaration",
            "ParameterDeclarationAbstract", "Condition")) {
        foreach (i, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("ParametersAndQualifiers")) {
        SemanticRunInfo semanticRun = semantic;
        Scope parameterScope;
        if (tree !in semantic.currentScope.childScopeByTree)
        {
            parameterScope = new Scope(tree, instanceConditionHere);
            semantic.currentScope.childScopeByTree[tree] = parameterScope;
        }
        else
        {
            parameterScope = semantic.currentScope.childScopeByTree[tree];
            parameterScope.scopeCondition = semantic.logicSystem.or(parameterScope.scopeCondition,
                instanceConditionHere);
        }

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            if (!realParent.isValid || realParent.name != "FunctionDeclarator")
                continue;
            Tree declarator = realParent;
            while (declarator.isValid && declarator.hasChildWithName("innerDeclarator"))
            {
                declarator = ppVersion.chooseTree(declarator.childByName("innerDeclarator"));
            }
            if (!declarator.isValid)
                continue;

            if (declarator.nonterminalID == nonterminalIDFor!"DeclaratorId" && declarator.hasChildWithName("nestedName"))
            {
                auto namespaceType = semantic.extraInfo(declarator.childByName("nestedName")).type;

                if (namespaceType.kind == TypeKind.record)
                {
                    RecordType recordType = cast(RecordType) namespaceType.type;
                    auto extraScope = scopeForRecord(recordType, ppVersion, semantic);
                    size_t startIndex = 0;
                    if (extraScope !is null)
                        startIndex = parameterScope.extraParentScopes.add(ppVersion.condition,
                            ExtraScope(ExtraScopeType.namespace, extraScope),
                            ppVersion.logicSystem, startIndex) + 1;
                }
            }
        }

        {
            string name = text("@funcparams", semantic.currentScope.numFunctionParamScopes);
            semantic.currentScope.numFunctionParamScopes++;
            assert(name !in semantic.currentScope.subScopes);

            semantic.currentScope.subScopes[name] ~= semantic.currentScope.childScopeByTree[tree];

            createScope(semantic.currentScope.childScopeByTree[tree],
                semantic.currentScope, semantic.logicSystem);
        }

        foreach (i, ref c; tree.childs)
        {
            semanticRun.currentScope = parameterScope;

            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchNonterminals!("TemplateDeclaration")) {
        SemanticRunInfo semanticRun = semantic;
        Scope parameterScope;
        if (tree !in semantic.currentScope.childScopeByTree)
        {
            parameterScope = new Scope(tree, instanceConditionHere);
            semantic.currentScope.childScopeByTree[tree] = parameterScope;
        }
        else
        {
            parameterScope = semantic.currentScope.childScopeByTree[tree];
            parameterScope.scopeCondition = semantic.logicSystem.or(parameterScope.scopeCondition,
                instanceConditionHere);
        }

        {
            string name = text("@templateparams", semantic.currentScope.numTemplateParamScopes);
            semantic.currentScope.numTemplateParamScopes++;
            assert(name !in semantic.currentScope.subScopes);

            semantic.currentScope.subScopes[name] ~= semantic.currentScope.childScopeByTree[tree];

            createScope(semantic.currentScope.childScopeByTree[tree],
                semantic.currentScope, semantic.logicSystem);
        }

        foreach (i, ref c; tree.childs)
        {
            semanticRun.currentScope = parameterScope;
            parameterScope.currentlyInsideParams = i <= 3;

            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchNonterminals!("*Declarator", "FunctionDeclaratorTrailing"),
            MatchRealParentNonterminals!("SimpleDeclaration*",
            "MemberDeclaration*", "FunctionDefinitionHead",
            "ParameterDeclaration", "ParameterDeclarationAbstract", "Condition")) {
        foreach (k, ref c; tree.childs)
        {
            if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitDeclarator" && k == 1)
            {
            }
            else
                runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            Tree parent2 = realParent;
            while (parent2.isValid && (parent2.name.startsWith("SimpleDeclaration")
                || parent2.name.startsWith("MemberDeclaration")
                || parent2.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
                || parent2.nonterminalID == nonterminalIDFor!"FunctionDefinitionGlobal"
                || parent2.nonterminalID == nonterminalIDFor!"ParameterDeclaration"
                || parent2.name.startsWith("ParameterDeclarationAbstract")
                || parent2.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead"))
                parent2 = getRealParent(parent2, semantic);

            SimpleDeclarationInfo info;
            info.start = realParent.start;
            info.tree = realParent;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iterateTreeConditions!analyzeSimpleDeclaration(realParent,
                ppVersion.condition, semantic, ppVersion, info);

            DeclaratorInfo declaratorInfo;

            QualType type = getDeclSpecType(semantic, info);
            QualType declaredType;

            iteratePPVersions!analyzeDeclarator(tree, ppVersion, semantic, declaratorInfo, type);

            if (declaratorInfo.isTemplateSpecialization)
            {
                continue;
            }

            declaratorInfo.namespaceType = chooseType(declaratorInfo.namespaceType,
                ppVersion, false);

            type = declaratorInfo.type;

            if (realParent.nonterminalID.nonterminalIDAmong!("ParameterDeclaration", "ParameterDeclarationAbstract"))
            {
                auto type2 = chooseType(type, ppVersion, true);
                if (type2.type !is null && type2.kind == TypeKind.array)
                {
                    auto atype = cast(ArrayType) type2.type;
                    type = QualType(semantic.getPointerType(atype.next), type2.qualifiers);
                }
            }

            Scope targetScope = semantic.currentScope;
            Scope[] templateScopes;
            while (targetScope.tree.isValid
                && targetScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration"
                && !targetScope.currentlyInsideParams)
            {
                templateScopes ~= targetScope;
                targetScope = targetScope.parentScope;
            }

            DeclarationKey dk;

            dk.flags |= info.flags;
            dk.flags |= declaratorInfo.flags;
            if ((info.flags & DeclarationFlags.typedef_) != 0)
            {
                dk.type = DeclarationType.type;
            }
            else
                dk.type = DeclarationType.varOrFunc;

            dk.bitfieldSize = declaratorInfo.bitfieldSize;

            Tree declarationTree = realParent;
            if (realParent.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead")
            {
                declarationTree = getRealParent(declarationTree, semantic);
            }
            assert(declarationTree.isValid);

            if (type.type !is null && isInCorrectVersion(ppVersion,
                typeKindIs(type.type, TypeKind.function_, semantic.logicSystem, false)))
                dk.flags |= DeclarationFlags.function_;

            if (parent2.isValid && parent2.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
                dk.flags |= DeclarationFlags.template_;

            if (realParent.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead")
            {
                Tree parentX = getRealParent(realParent, semantic);
                assert(parentX.name.startsWith("FunctionDefinition"));
                if (parentX.childs.length == 4 && parentX.childs[2].content == "0")
                    dk.flags |= DeclarationFlags.abstract_;
            }

            dk.tree = declarationTree;
            dk.declaratorTree = tree;
            dk.name = declaratorInfo.name;
            if (!info.hasAnyTypeSpecifier && declaratorInfo.name.length
                && declaratorInfo.name != "operator cast")
            {
                if (declaratorInfo.isDestructor)
                    dk.name = "~" ~ dk.name;
                dk.name = "$norettype:" ~ dk.name;
            }
            dk.scope_ = targetScope;

            immutable(Formula)* oldCondition = semantic.logicSystem.false_;
            Declaration d = addOrUpdateDeclaration(dk, declarationTree, ppVersion.condition, true,
                targetScope, semantic, declaratorInfo.namespaces.length == 0, &oldCondition);

            if (dk.name.length)
            {
                d.location = declaratorInfo.identifierLocation;
            }
            else
            {
                d.location = declarationTree.location;
            }

            if ((info.flags & DeclarationFlags.typedef_) != 0)
            {
                QualType nextType = type;
                TypedefType typedefType = semantic.getTypedefType(d.declarationSet, [], nextType);
                declaredType = QualType(typedefType, Qualifiers.none);
            }

            d.type2 = combineTypes(d.type2, type, oldCondition, ppVersion.condition, semantic);
            d.declaredType = combineTypes(d.declaredType, declaredType,
                oldCondition, ppVersion.condition, semantic);

            if ((d.flags & DeclarationFlags.function_) != 0
                && (info.flags & DeclarationFlags.typedef_) == 0
                && realParent.name != "FunctionDefinitionHead")
                d.flags |= DeclarationFlags.forward;

            if (d.flags & DeclarationFlags.function_)
                d.flags &= ~DeclarationFlags.extern_;

            if ((d.flags & DeclarationFlags.extern_) != 0
                && (d.flags & DeclarationFlags.function_) == 0
                && (info.flags & DeclarationFlags.typedef_) == 0)
                d.flags |= DeclarationFlags.forward;

            Scope targetScope2 = targetScope;
            if (declaratorInfo.namespaces.length)
            {
                targetScope2 = null;
                if (declaratorInfo.namespaceType.kind == TypeKind.record)
                {
                    RecordType recordType = cast(RecordType) declaratorInfo.namespaceType.type;
                    targetScope2 = scopeForRecord(recordType, ppVersion, semantic);
                }
                if (declaratorInfo.namespaceType.kind == TypeKind.namespace)
                {
                    NamespaceType namespaceType = cast(NamespaceType) declaratorInfo
                        .namespaceType.type;
                    targetScope2 = scopeForRecord(namespaceType, ppVersion, semantic);
                }
            }

            FilterTypeFlags filterFlags = FilterTypeFlags.fakeTemplateScope | FilterTypeFlags.replaceRealTypes | FilterTypeFlags.simplifyFunctionType | FilterTypeFlags.removeTypedef | FilterTypeFlags.removeTrees;

            void findParentFuncs(Scope s, immutable(Formula)* condition)
            {
                if (s is null)
                    return;
                foreach (e; s.extraParentScopes.entries)
                    if (e.data.type == ExtraScopeType.parentClass && !semantic.logicSystem.and(condition, e.condition).isFalse)
                    {
                        auto s2 = e.data.scope_;
                        findParentFuncs(s2, semantic.logicSystem.and(condition, e.condition));

                        foreach (e2; s2.symbolEntries(d.name))
                        {
                            auto d2 = e2.data;
                            if (d2.type != d.type)
                                continue;
                            if ((d2.flags & DeclarationFlags.typedef_) != (d.flags & DeclarationFlags.typedef_))
                                continue;
                            if (filterType(d.type2, condition, semantic, filterFlags)
                                !is filterType(d2.type2, condition, semantic, filterFlags))
                                continue;
                            auto condition2 = ppVersion.logicSystem.and(condition, d2.condition);
                            if (condition2.isFalse)
                                continue;
                            if (d2.flags & DeclarationFlags.virtual)
                            {
                                d.flags |= DeclarationFlags.override_;
                            }
                        }
                    }
            }
            if ((d.flags & DeclarationFlags.function_) != 0)
                findParentFuncs(targetScope2, ppVersion.condition);

            if (d.name && targetScope2 !is null)
            {
                foreach (e; targetScope2.symbolEntries(d.name))
                {
                    auto d2 = e.data;
                    if (d2.type != d.type)
                        continue;
                    if ((d2.flags & DeclarationFlags.typedef_) != (d.flags & DeclarationFlags.typedef_))
                        continue;
                    auto condition = ppVersion.logicSystem.and(ppVersion.condition, d2.condition);
                    if (condition.isFalse)
                        continue;
                    if (filterType(d.type2, condition, semantic, filterFlags)
                        !is filterType(d2.type2, condition, semantic, filterFlags))
                        continue;
                    if (d.name == "operator cast")
                        continue;
                    if ((d.flags & DeclarationFlags.forward) != 0
                        && (d2.flags & DeclarationFlags.forward) == 0)
                    {
                        d.realDeclaration.add(condition, d2, semantic.logicSystem);
                    }
                    if ((d.flags & DeclarationFlags.forward) == 0
                        && (d2.flags & DeclarationFlags.forward) != 0)
                    {
                        d2.realDeclaration.add(condition, d, semantic.logicSystem);
                        if ((d.flags & DeclarationFlags.function_) != 0
                            && (d2.flags & DeclarationFlags.function_) != 0)
                        {
                            addFunctionParamReclDecls(d, d2, ppVersion.condition, semantic);
                            if (d2.flags & DeclarationFlags.static_)
                                d.flags |= DeclarationFlags.static_;
                        }
                    }
                }
            }

            if (realParent.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead")
            {
                Tree functionDefinition = getRealParent(realParent, semantic);
                assert(functionDefinition.name.startsWith("FunctionDefinition"));
                Scope functionScope;
                if (functionDefinition !in targetScope.childScopeByTree)
                {
                    functionScope = createScope(functionDefinition,
                        targetScope, instanceConditionHere, semantic.logicSystem);
                    targetScope.childScopeByTree[functionDefinition] = functionScope;
                }
                else
                {
                    functionScope = targetScope.childScopeByTree[functionDefinition];
                    functionScope.scopeCondition = semantic.logicSystem.or(functionScope.scopeCondition,
                        instanceConditionHere);
                }
                string name = text(declaratorInfo.name, "@func", targetScope.numFunctionScopes);
                targetScope.numFunctionScopes++;
                assert(name !in targetScope.subScopes);
                targetScope.subScopes[name] ~= functionScope;

                size_t startIndex = 0;
                if (declaratorInfo.parameterScope !is null)
                    startIndex = functionScope.extraParentScopes.add(ppVersion.condition,
                        ExtraScope(ExtraScopeType.parameter,
                        declaratorInfo.parameterScope), ppVersion.logicSystem, startIndex) + 1;
                foreach (s; templateScopes)
                    startIndex = functionScope.extraParentScopes.add(ppVersion.condition,
                        ExtraScope(ExtraScopeType.template_, s), ppVersion.logicSystem, startIndex)
                        + 1;
                if (declaratorInfo.namespaces.length && targetScope2 !is null)
                    startIndex = functionScope.extraParentScopes.add(ppVersion.condition,
                        ExtraScope(ExtraScopeType.namespace, targetScope2),
                        ppVersion.logicSystem, startIndex) + 1;
            }

            combinedType = combineTypes(combinedType, type, null, ppVersion.condition, semantic);

            i++;
            if (i > 200)
            {
                writeln("many combinations");
                return;
            }
        }

        updateType(extraInfoHere.type, combinedType);

        foreach (k, ref c; tree.childs)
        {
            if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitDeclarator" && k == 1)
                runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("AliasDeclaration")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        Scope targetScope = semantic.currentScope;
        Scope[] templateScopes;
        while (targetScope.tree.isValid && targetScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration"
            && !targetScope.currentlyInsideParams)
        {
            templateScopes ~= targetScope;
            targetScope = targetScope.parentScope;
        }

        DeclarationKey dk;

        dk.type = DeclarationType.type;

        if (realParent.isValid && realParent.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
            dk.flags |= DeclarationFlags.template_;

        dk.tree = tree;
        dk.declaratorTree = tree;
        dk.name = tree.childs[1].content;
        dk.scope_ = targetScope;

        immutable(Formula)* oldCondition = semantic.logicSystem.false_;
        Declaration d = addOrUpdateDeclaration(dk, tree, condition, true,
            targetScope, semantic, true, &oldCondition);

        d.location = tree.childs[1].location;

        QualType nextType = semantic.extraInfo(tree.childs[3]).type;
        TypedefType typedefType = semantic.getTypedefType(d.declarationSet, [], nextType);
        QualType declaredType = QualType(typedefType, Qualifiers.none);

        d.type2 = combineTypes(d.type2, declaredType, oldCondition, condition, semantic);
        d.declaredType = combineTypes(d.declaredType, declaredType,
            oldCondition, condition, semantic);
    }, (MatchNonterminals!("ClassSpecifier", "ElaboratedTypeSpecifier",
            "EnumSpecifier", "TypeParameter")) {
        bool oldCollectingDelayedSemantics = semantic.collectingDelayedSemantics;
        auto oldDelayedSemantics = semantic.delayedSemantics;
        semantic.collectingDelayedSemantics = false;
        semantic.delayedSemantics = [];
        scope (success)
        {
            semantic.collectingDelayedSemantics = oldCollectingDelayedSemantics;
            semantic.delayedSemantics = oldDelayedSemantics;
        }
        size_t headChilds = (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier") ? tree.childs.length : 1;
        foreach (ref c; tree.childs[0 .. headChilds])
        {
            runSemantic(semantic, c, tree, condition);
        }

        bool isTemplateSpecializationHere;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            ClassSpecifierInfo classSpecifierInfo;
            iteratePPVersions!analyzeClassSpecifier(tree, ppVersion, semantic, classSpecifierInfo);

            if (iteratePPVersions!isTemplateSpecialization(tree, ppVersion))
            {
                isTemplateSpecializationHere = true;
            }

            classSpecifierInfo.namespaceType = chooseType(classSpecifierInfo.namespaceType,
                ppVersion, false);

            Tree wrapperDeclaration = findWrappingDeclaration(tree, semantic);
            SimpleDeclarationInfo wrappperInfo;
            iterateTreeConditions!analyzeSimpleDeclaration(wrapperDeclaration,
                ppVersion.condition, semantic, ppVersion, wrappperInfo);

            if (wrappperInfo.flags & DeclarationFlags.friend)
                continue;

            Tree parent2 = getRealParent(realParent, semantic);
            size_t parent3Index;
            Tree parent3 = getRealParent(parent2, semantic, &parent3Index);

            Scope targetScope = semantic.currentScope;
            Scope[] templateScopes;
            while (targetScope.tree.isValid
                && targetScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration"
                && !targetScope.currentlyInsideParams)
            {
                templateScopes ~= targetScope;
                targetScope = targetScope.parentScope;
            }

            if (tree.nonterminalID.nonterminalIDAmong!("ClassSpecifier", "EnumSpecifier") && !semantic.isCPlusPlus)
            {
                while (targetScope.tree.isValid
                    && targetScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier"
                    && targetScope.parentScope !is null)
                    targetScope = targetScope.parentScope;
            }
            else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier"
                && parent2.nonterminalID.nonterminalIDAmong!("SimpleDeclaration1", "MemberDeclaration1",
                    "UnaryExpression", "CastExpressionHead",
                    "ParameterDeclarationAbstract", "ParameterDeclaration",
                    "Condition", "MemberDeclaration2")
                && (!parent3.isValid || parent3Index != 2 || parent3.nonterminalID != ParserWrapper.nonterminalIDFor!"TemplateDeclaration")
                && classSpecifierInfo.className && (!semantic.isCPlusPlus
                    || !parent2.nonterminalID.nonterminalIDAmong!("SimpleDeclaration3", "MemberDeclaration2")))
            {
                while (targetScope.parentScope !is null)
                {
                    immutable(Formula)* conditionHasSibling = semantic.logicSystem.false_;
                    foreach (combination2; iterateCombinations())
                    {
                        IteratePPVersions ppVersion2 = IteratePPVersions(combination2,
                            semantic.logicSystem, ppVersion.condition,
                            semantic.instanceCondition, semantic.mergedTreeDatas);

                        Declaration[] ds = lookupName(classSpecifierInfo.className,
                            targetScope, ppVersion2, LookupNameFlags.followForwardScopes);

                        foreach (d2; ds)
                        {
                            if (d2.type != DeclarationType.type)
                                continue;
                            if ((d2.flags & DeclarationFlags.typedef_) != 0)
                                continue;
                            auto condition = semantic.logicSystem.and(ppVersion2.condition,
                                d2.condition);
                            if (d2.scope_ is targetScope)
                            {
                                conditionHasSibling = semantic.logicSystem.or(conditionHasSibling,
                                    condition);
                            }
                        }
                    }
                    if (isInCorrectVersion(ppVersion, conditionHasSibling))
                        break;
                    targetScope = targetScope.parentScope;
                }
            }

            Scope targetScope2 = targetScope;
            if (classSpecifierInfo.namespaces.length)
            {
                targetScope2 = null;
                if (classSpecifierInfo.namespaceType.kind == TypeKind.record)
                {
                    RecordType recordType = cast(RecordType) classSpecifierInfo.namespaceType.type;
                    targetScope2 = scopeForRecord(recordType, ppVersion, semantic);
                }
            }

            if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier")
            {
                Scope classScope;
                if (tree !in targetScope.childScopeByTree)
                {
                    classScope = createScope(tree, targetScope,
                        instanceConditionHere, semantic.logicSystem);
                    targetScope.childScopeByTree[tree] = classScope;
                }
                else
                {
                    classScope = targetScope.childScopeByTree[tree];
                    classScope.scopeCondition = semantic.logicSystem.or(classScope.scopeCondition,
                        instanceConditionHere);
                }
                if (classSpecifierInfo.className !in targetScope.subScopes)
                    targetScope.subScopes[classSpecifierInfo.className] = [];
                targetScope.subScopes[classSpecifierInfo.className].addOnce(
                    targetScope.childScopeByTree[tree]);
                classScope.className.add(ppVersion.condition,
                    classSpecifierInfo.className, semantic.logicSystem);

                size_t startIndex = 0;
                foreach (s; templateScopes)
                    startIndex = classScope.extraParentScopes.add(ppVersion.condition,
                        ExtraScope(ExtraScopeType.template_, s), ppVersion.logicSystem, startIndex)
                        + 1;
                foreach (t; classSpecifierInfo.parentTypes)
                {
                    t = chooseType(t, ppVersion, true);
                    if (t.kind == TypeKind.record)
                    {
                        RecordType recordType = cast(RecordType) t.type;

                        Scope scope_ = scopeForRecord(recordType, ppVersion, semantic);

                        if (scope_ !is null && scope_.tree !is tree)
                            startIndex = classScope.extraParentScopes.add(ppVersion.condition,
                                ExtraScope(ExtraScopeType.parentClass, scope_),
                                ppVersion.logicSystem, startIndex) + 1;
                    }
                }
                if (classSpecifierInfo.namespaces.length && targetScope2 !is null)
                    startIndex = classScope.extraParentScopes.add(ppVersion.condition,
                        ExtraScope(ExtraScopeType.namespace, targetScope2),
                        ppVersion.logicSystem, startIndex) + 1;
            }

            DeclarationKey dk;

            dk.type = DeclarationType.type;
            dk.tree = tree;
            if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier")
                dk.flags |= DeclarationFlags.forward;
            if (templateScopes.length)
                dk.flags |= DeclarationFlags.template_;
            if (isTemplateSpecializationHere)
                dk.flags |= DeclarationFlags.templateSpecialization;
            if (wrappperInfo.flags & DeclarationFlags.friend)
                dk.flags |= DeclarationFlags.friend;
            dk.name = classSpecifierInfo.className;
            dk.scope_ = targetScope;

            immutable(Formula)* oldCondition = semantic.logicSystem.false_;
            Declaration d = addOrUpdateDeclaration(dk, wrapperDeclaration, ppVersion.condition, true, targetScope,
                semantic, classSpecifierInfo.namespaces.length == 0, &oldCondition);
            d.location = classSpecifierInfo.identifierLocation;
            if (d.location.context is null)
                d.location = tree.location;

            assert(d.declarationSet.entries.length);
            assert(d.declarationSet.scope_ !is null);
            RecordType type = semantic.getRecordType(d.declarationSet, []);
            updateType(extraInfoHere.type, combineTypes(extraInfoHere.type,
                QualType(type, Qualifiers.none), null, ppVersion.condition, semantic));
            //enforce(info.type is null);
            //info.type = type;

            d.declaredType = combineTypes(d.declaredType, QualType(type,
                Qualifiers.none), oldCondition, ppVersion.condition, semantic);

            if (d.name && targetScope2 !is null && d.name in targetScope2.symbols)
            {
                foreach (e; targetScope2.symbols[d.name].entries)
                {
                    auto d2 = e.data;
                    if (d2.type != d.type)
                        continue;
                    if ((d2.flags & DeclarationFlags.typedef_) != (d.flags & DeclarationFlags.typedef_))
                        continue;
                    auto condition = semantic.logicSystem.and(ppVersion.condition, d2.condition);
                    if (condition.isFalse)
                        continue;
                    if ((d.flags & DeclarationFlags.forward) != 0
                        && (d2.flags & DeclarationFlags.forward) == 0)
                    {
                        d.realDeclaration.add(condition, d2, semantic.logicSystem);
                    }
                    if ((d.flags & DeclarationFlags.forward) == 0
                        && (d2.flags & DeclarationFlags.forward) != 0)
                    {
                        d2.realDeclaration.add(condition, d, semantic.logicSystem);
                    }
                }
                if ((d.flags & DeclarationFlags.forward) == 0 && d.type == DeclarationType.type)
                {
                    foreach (e; targetScope2.symbols[d.name].entriesRedundant)
                    {
                        auto d2 = e.data;
                        if (d2.type != d.type)
                            continue;
                        if ((d2.flags & DeclarationFlags.typedef_) != (
                            d.flags & DeclarationFlags.typedef_))
                            continue;
                        auto condition = semantic.logicSystem.and(ppVersion.condition,
                            d2.condition);
                        if (condition.isFalse)
                            continue;
                        if ((d2.flags & DeclarationFlags.forward) != 0)
                        {
                            d2.realDeclaration.add(condition, d, semantic.logicSystem);
                        }
                    }
                }
            }
        }

        foreach (ref c; tree.childs[headChilds .. $])
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("OriginalNamespaceDefinition")) {
        string name = tree.childs[2].content;

        Scope parentScope = semantic.currentScope;

        Scope namespaceScope;
        if (name !in parentScope.childNamespaces)
        {
            namespaceScope = createScope(Tree.init, parentScope,
                instanceConditionHere, semantic.logicSystem);
            parentScope.childNamespaces[name] = namespaceScope;
        }
        else
        {
            namespaceScope = parentScope.childNamespaces[name];
            namespaceScope.scopeCondition = semantic.logicSystem.or(namespaceScope.scopeCondition,
                condition);
        }
        if (name !in parentScope.subScopes)
            parentScope.subScopes[name] = [];
        parentScope.subScopes[name].addOnce(namespaceScope);
        namespaceScope.className.add(condition, name, semantic.logicSystem);
        assert(namespaceScope.className.entries.length == 1);

        if (tree.childs[0].isValid && tree.childs[0].content == "inline")
            parentScope.extraParentScopes.add(condition,
                ExtraScope(ExtraScopeType.inlineNamespace, namespaceScope),
                semantic.logicSystem);

        {
            DeclarationKey dk;
            dk.type = DeclarationType.namespace;
            dk.name = name;
            dk.scope_ = semantic.currentScope;

            immutable(Formula)* oldCondition = semantic.logicSystem.false_;
            Declaration d = addOrUpdateDeclaration(dk, tree, condition, false,
                semantic.currentScope, semantic, true, &oldCondition);

            d.location = tree.location;

            NamespaceType namespaceType = semantic.getNamespaceType(d.declarationSet);
            QualType declaredType = QualType(namespaceType, Qualifiers.none);

            d.type2 = combineTypes(d.type2, declaredType, oldCondition, condition, semantic);
            d.declaredType = combineTypes(d.declaredType, declaredType,
                oldCondition, condition, semantic);
        }

        {
            DeclarationKey dk;
            dk.declaratorTree = tree;
            dk.type = DeclarationType.namespaceBegin;
            dk.scope_ = semantic.currentScope;

            Declaration d = addOrUpdateDeclaration(dk, tree.childs[1],
                condition, false, semantic.currentScope, semantic);

            d.location = tree.childs[1].location;
        }
        {
            DeclarationKey dk;
            dk.tree = tree.childs[$ - 1];
            dk.type = DeclarationType.namespaceEnd;
            dk.scope_ = semantic.currentScope;

            auto dkInCache = dk in semantic.declarationCache;
            Declaration d = addOrUpdateDeclaration(dk, tree.childs[$ - 1],
                condition, false, semantic.currentScope, semantic);

            d.location = dk.tree.location;
        }

        SemanticRunInfo semanticRun = semantic;
        semanticRun.currentScope = namespaceScope;

        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchNonterminals!("Enumerator")) {
        Tree enumSpecifier = tree;
        while (enumSpecifier.isValid && (enumSpecifier.nodeType != NodeType.nonterminal
            || enumSpecifier.name != "EnumSpecifier"))
            enumSpecifier = semantic.extraInfo(enumSpecifier).parent;

        Scope targetScope = semantic.currentScope;
        while (!semantic.isCPlusPlus && targetScope.tree.isValid
            && targetScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier" && targetScope.parentScope !is null)
            targetScope = targetScope.parentScope;

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            DeclarationKey dk;
            dk.type = DeclarationType.varOrFunc;
            dk.tree = tree;
            dk.declaratorTree = tree;
            dk.flags |= DeclarationFlags.enumerator;
            dk.name = tree.childs[0].content;
            dk.scope_ = targetScope;

            immutable(Formula)* oldCondition = semantic.logicSystem.false_;
            auto dkInCache = dk in semantic.declarationCache;
            Declaration d;
            if (dkInCache)
            {
                d = *dkInCache;

                oldCondition = d.condition;
                d.condition = semantic.logicSystem.or(d.condition, ppVersion.condition);
                dk.scope_.updateDeclarationCondition(dk.name, d.condition, d,
                    ppVersion.logicSystem);
            }
            else
            {
                d = new Declaration();
                d.condition = ppVersion.condition;
                semantic.declarationCache[dk] = d;
                d.key = dk;

                dk.scope_.addDeclaration(dk.name, ppVersion.condition, d, ppVersion.logicSystem);
                extraInfoHere.declarations ~= d;
            }

            d.location = tree.location;
            d.type2 = combineTypes(d.type2, semantic.extraInfo(enumSpecifier)
                .type, oldCondition, ppVersion.condition, semantic);
            updateType(extraInfoHere.type, combineTypes(extraInfoHere.type,
                semantic.extraInfo(enumSpecifier).type, null, ppVersion.condition, semantic));

            foreach (ref c; tree.childs)
            {
                runSemantic(semantic, c, tree, condition);
            }
        }
    }, (MatchNonterminals!("FunctionBody")) {
        /*foreach (i;0..indent)
            write(" ");
        writeln("init func scope ", cast(void*)tree, " ", cast(void*)semantic.scopeByTree[tree]);*/

        if (semantic.collectingDelayedSemantics)
        {
            semantic.delayedSemantics ~= DelayedSemantic(semantic, tree, parent, condition);
            semantic.treesVisited.remove(tree);
            return;
        }

        Scope parentScope = semantic.currentScope;
        while (parentScope.tree.isValid
            && parentScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration"
            && !parentScope.currentlyInsideParams)
            parentScope = parentScope.parentScope;

        SemanticRunInfo semanticRun = semantic;

        if (realParent !in parentScope.childScopeByTree)
        {
            Scope functionScope = createScope(realParent, parentScope,
                instanceConditionHere, semantic.logicSystem);
            parentScope.childScopeByTree[realParent] = functionScope;
        }

        assert(realParent in parentScope.childScopeByTree, text(locationStr(tree.location)));
        semanticRun.currentScope = parentScope.childScopeByTree[realParent];

        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchNonterminals!("MemInitializer")) {
        Scope classScope = semantic.currentScope.parentScope;
        foreach (e; semantic.currentScope.extraParentScopes.entries)
        {
            if (e.data.type == ExtraScopeType.namespace
                && !semantic.logicSystem.and(e.condition, condition).isFalse)
            {
                enforce(semantic.logicSystem.and(e.condition.negated, condition).isFalse);
                classScope = e.data.scope_;
            }
        }
        SemanticRunInfo semanticRun = semantic;
        semanticRun.currentScope = classScope;

        runSemantic(semanticRun, tree.childs[0], tree, condition);

        foreach (ref c; tree.childs[1 .. $])
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("ClassBody")) {
        assert(realParent.nonterminalID == nonterminalIDFor!"ClassSpecifier");

        Scope parentScope = semantic.currentScope;
        while (parentScope.tree.isValid
            && parentScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration"
            && !parentScope.currentlyInsideParams)
            parentScope = parentScope.parentScope;
        if (!semantic.isCPlusPlus)
            while (parentScope.tree.isValid
                && parentScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier"
                && parentScope.parentScope !is null)
                parentScope = parentScope.parentScope;

        if (realParent !in parentScope.childScopeByTree)
            writeln("============== ", locationStr(realParent.start), " ", condition.toString);
        SemanticRunInfo semanticRun = semantic;
        semanticRun.currentScope = parentScope.childScopeByTree[realParent];

        assert(!semantic.collectingDelayedSemantics);
        assert(semantic.delayedSemantics.length == 0);
        semantic.collectingDelayedSemantics = true;
        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
        auto delayedSemantics = semantic.delayedSemantics;
        semantic.collectingDelayedSemantics = false;
        semantic.delayedSemantics = [];
        foreach (ref d; delayedSemantics)
        {
            runSemantic(d.semantic, d.tree, d.parent, d.condition);
        }
    }, (MatchNonterminals!("NameIdentifier")) {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].isToken == 1);
        string name = tree.childs[0].content;

        Tree parent2 = realParent;
        size_t indexInParent2 = indexInRealParent;
        while (parent2.isValid && ((parent2.nonterminalID == nonterminalIDFor!"SimpleTemplateId" && indexInParent2 == 0)
            || parent2.nonterminalID.nonterminalIDAmong!("SimpleTemplateId", "UnqualifiedId", "QualifiedId", "SimpleTypeSpecifierNoKeyword")
            || (parent2.nonterminalID == nonterminalIDFor!"PostfixExpression"
                && parent2.childs[1].nodeType == NodeType.token
                && parent2.childs[1].content.among(".", "->")
                && indexInParent2 && parent2.childs.length - 1)))
            parent2 = getRealParent(parent2, semantic, &indexInParent2);

        if (!parent2.isValid)
            return;
        if (parent2.name.canFind("Declarator")
            && !(parent2.nonterminalID == nonterminalIDFor!"ArrayDeclarator" && indexInParent2 == 2))
            return;
        if (parent2.nonterminalID == nonterminalIDFor!"ClassHeadName")
            return;

        if (name.among("__FILE__", "__FUNCTION__", "__DATE__", "__TIME__",
            "__func__", "__FUNCTION__", "__PRETTY_FUNCTION__"))
        {
            extraInfoHere.type = QualType(semantic.getArrayType(QualType(semantic.getBuiltinType("char"),
                Qualifiers.const_), Tree.init));
            return;
        }

        bool inExpression = !realParent.nonterminalID.nonterminalIDAmong!("ArrayDeclarator");

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            CheckValidDeclarationInfo info;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            QualType contextType = extraInfoHere.contextType;

            if (contextType.type is null)
            {
                if (realParent.isValid && realParent.nonterminalID == nonterminalIDFor!"PostfixExpression"
                    && indexInRealParent >= 2 && realParent.childs[1].content.among(".", "->"))
                    continue;
            }

            Type recordType = recordTypeFromType(ppVersion, semantic, contextType);
            if (contextType.type !is null && recordType is null)
                continue;

            Scope scope_ = semantic.currentScope;
            if (recordType !is null)
            {
                scope_ = scopeForRecord(recordType, ppVersion, semantic);
            }

            Tree[] parameterExprs;
            bool hasParameterExprs;
            if (parent2.isValid && parent2.nonterminalID == nonterminalIDFor!"PostfixExpression"
                && parent2.childs.length == 4
                && parent2.childs[1].content == "(" && indexInParent2 == 0)
            {
                bool hasNonterminal;
                iteratePPVersions!collectParameterExprs(parent2.childs[2], ppVersion, semantic,
                    parameterExprs, hasNonterminal);
                hasParameterExprs = true;
            }

            if (scope_ !is null)
            {
                Declaration[] ds = lookupName(name, scope_, ppVersion,
                    LookupNameFlags.followForwardScopes | ((recordType is null)
                    ? LookupNameFlags.none : LookupNameFlags.onlyExtraParents));

                immutable(Formula)* conditionType = semantic.logicSystem.false_;
                immutable(Formula)* conditionNonType = semantic.logicSystem.false_;

                foreach (d; ds)
                {
                    auto condition = ppVersion.logicSystem.and(ppVersion.condition, d.condition);
                    if (d.type == DeclarationType.type)
                        conditionType = semantic.logicSystem.or(conditionType, condition);
                    else
                        conditionNonType = semantic.logicSystem.or(conditionNonType, condition);
                }

                bool typeAllowed = isInCorrectVersion(ppVersion, conditionNonType.negated);

                QualType functionResultType;
                QualType[] functionParameters;
                bool firstFunctionType = true;
                int bestFunctionTypeMatch = 0;
                functionParameters.length = parameterExprs.length;
                immutable(Formula)* conditionFunction = semantic.logicSystem.false_;

                nameIdentifierOuterLoop: foreach (i, d; ds)
                {
                    if (!isInCorrectVersion(ppVersion, d.condition))
                        continue;
                    immutable(Formula)* condition = ppVersion.logicSystem.and(ppVersion.condition,
                        d.condition);
                    extraInfoHere.referenced.add(condition, d.declarationSet,
                        semantic.logicSystem);

                    void setType(ref QualType t, QualType t2, bool isResult)
                    {
                        if (firstFunctionType)
                            t = t2;
                        else
                        {
                            if (t != t2)
                                t = createCommonType(t, t2, ppVersion, semantic, isResult);
                        }
                    }

                    bool functionPossible(FunctionType functionType)
                    {
                        if (parameterExprs.length < functionType.neededParameters)
                            return false;
                        if (!functionType.isVariadic
                            && parameterExprs.length > functionType.parameters.length)
                            return false;
                        int typeMatch = 1000;
                        foreach (j; 0 .. parameterExprs.length)
                        {
                            if (j >= functionType.parameters.length)
                                break;
                            if (!isImplicitConversionPossible(functionType.parameters[j],
                                semantic.extraInfo(parameterExprs[j]).type, ppVersion, semantic))
                                return false;
                            int typeMatch2 = 1000;
                            if (!isSameType(functionType.parameters[j],
                                semantic.extraInfo(parameterExprs[j]).type, ppVersion, semantic))
                            {
                                QualType toType = chooseType(functionType.parameters[j],
                                    ppVersion, true);
                                QualType fromType = chooseType(semantic.extraInfo(parameterExprs[j])
                                    .type, ppVersion, true);
                                if (toType.kind == TypeKind.builtin
                                    && fromType.kind == TypeKind.builtin)
                                    typeMatch2 = 1;
                                else
                                    typeMatch2 = 0;
                            }
                            if (typeMatch2 < typeMatch)
                                typeMatch = typeMatch2;
                        }
                        if (typeMatch < bestFunctionTypeMatch)
                            return false;
                        if (typeMatch > bestFunctionTypeMatch)
                        {
                            bestFunctionTypeMatch = typeMatch;
                            firstFunctionType = true;
                        }
                        return true;
                    }

                    void addFunctionParams(FunctionType functionType)
                    {
                        foreach (j; 0 .. functionParameters.length)
                        {
                            if (j < functionType.parameters.length)
                                setType(functionParameters[j], functionType.parameters[j], false);
                            else
                                setType(functionParameters[j], QualType.init, false);
                        }
                    }

                    auto expectedType = chooseType(d.type2, ppVersion, true);
                    if (hasParameterExprs && d.type == DeclarationType.varOrFunc
                        && expectedType.kind == TypeKind.function_)
                    {
                        auto functionType = cast(FunctionType) expectedType.type;
                        if (!functionPossible(functionType))
                            continue;

                        setType(functionResultType, functionType.resultType, true);
                        addFunctionParams(functionType);

                        conditionFunction = semantic.logicSystem.or(conditionFunction, condition);
                        firstFunctionType = false;
                    }
                    else if (typeAllowed && hasParameterExprs && d.type == DeclarationType.type
                        && chooseType(d.declaredType, ppVersion, true).kind == TypeKind.record)
                    {
                        QualType declaredType2 = chooseType(d.declaredType, ppVersion, true);
                        if (declaredType2.kind == TypeKind.record)
                        {
                            Scope s = scopeForRecord(declaredType2.type, ppVersion, semantic);
                            if (s !is null)
                            {
                                auto ds2 = "$norettype:" ~ declaredType2.name in s.symbols;
                                if (ds2)
                                {
                                    foreach (e2; ds2.entries)
                                    {
                                        auto ftype = chooseType(e2.data.type2, ppVersion, true);
                                        if (ftype.kind == TypeKind.function_)
                                        {
                                            auto functionType = cast(FunctionType) ftype.type;

                                            if (!functionPossible(functionType))
                                                continue;
                                            addFunctionParams(functionType);
                                            setType(functionResultType, d.declaredType, true);
                                            conditionFunction = semantic.logicSystem.or(conditionFunction,
                                                condition);
                                        }
                                    }
                                }
                            }
                        }

                        setType(functionResultType, d.declaredType, true);
                        conditionFunction = semantic.logicSystem.or(conditionFunction, condition);
                        firstFunctionType = false;
                    }
                    else
                    {
                        if (d.type == DeclarationType.type)
                            condition = semantic.logicSystem.and(condition,
                                conditionNonType.negated);
                        QualType type2 = d.declaredType;
                        if (type2.type is null)
                            type2 = d.type2;
                        if (d.type == DeclarationType.type)
                            type2.qualifiers |= Qualifiers.noThis;
                        combinedType = combineTypes(combinedType, type2, null,
                            semantic.logicSystem.and(condition, ppVersion.condition), semantic);
                    }
                }
                if (hasParameterExprs && !conditionFunction.isFalse)
                {
                    QualType type2 = QualType(semantic.getFunctionType(functionResultType,
                        functionParameters, false, false, false, false, functionParameters.length));
                    if (isInCorrectVersion(ppVersion, conditionNonType.negated))
                        type2.qualifiers |= Qualifiers.noThis;
                    combinedType = combineTypes(combinedType, type2, null,
                        semantic.logicSystem.and(conditionFunction, ppVersion.condition), semantic);
                }
            }
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchNonterminals!("TypeKeyword")) {
        if (realParent.isValid && realParent.nonterminalID == nonterminalIDFor!"PostfixExpression" && indexInRealParent == 0)
        {
            SimpleDeclarationInfo info;
            info.builtinTypeParts ~= tree.childs[0].content;
            QualType t = getDeclSpecType(semantic, info);
            t.qualifiers |= Qualifiers.noThis;
            updateType(extraInfoHere.type, t);
        }
    }, (MatchNonterminals!("BraceOrEqualInitializer")) {
        updateType(extraInfoHere.type, semantic.extraInfo(realParent).type);
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("BracedInitList")) {
        updateType(extraInfoHere.type, semantic.extraInfo(realParent).type);

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            auto expectedType2 = chooseType(semantic.extraInfo(realParent).type, ppVersion, true);
            if (expectedType2.type !is null && expectedType2.kind == TypeKind.array)
            {
                auto t = cast(ArrayType) expectedType2.type;

                ConditionMap!Tree parameterExprs;
                immutable(Formula)* hasNonterminal = semantic.logicSystem.false_;
                collectParameterExprs2(tree.childs[1], ppVersion.condition,
                    semantic, parameterExprs, hasNonterminal);

                foreach (param; parameterExprs.entries)
                {
                    if (!param.data.isValid)
                        continue;
                    assert(param.data.nonterminalID.nonterminalIDAmong!("InitializerClause",
                        "InitializerClauseDesignator"));
                    auto extraInfoChild = &semantic.extraInfo(param.data);
                    extraInfoChild.type = combineTypes(extraInfoChild.type, t.next, null,
                        semantic.logicSystem.and(ppVersion.condition, param.condition), semantic);
                }
            }
            else if (expectedType2.type !is null && expectedType2.kind == TypeKind.record)
            {
                auto t = cast(RecordType) expectedType2.type;
                foreach (e; t.declarationSet.entries)
                {
                    if (e.data.type != DeclarationType.type)
                        continue;
                    if ((e.data.flags & DeclarationFlags.forward) != 0)
                        continue;
                    if (e.data.tree.name != "ClassSpecifier")
                        continue;
                    if (!isInCorrectVersion(ppVersion, e.condition))
                        continue;

                    ConditionMap!Declaration recordFields;
                    collectRecordFields2(e.data.tree, ppVersion.condition, semantic, recordFields);

                    ConditionMap!Tree parameterExprs;
                    immutable(Formula)* hasNonterminal = semantic.logicSystem.false_;
                    collectParameterExprs2(tree.childs[1], ppVersion.condition,
                        semantic, parameterExprs, hasNonterminal);

                    ConditionMap!size_t[2] currentRecordStart;
                    bool currentRecordStartI;
                    currentRecordStart[0].addNew(ppVersion.condition, 0, semantic.logicSystem);
                    currentRecordStart[1].addNew(ppVersion.condition, 0, semantic.logicSystem);

                    foreach (param; parameterExprs.entries)
                    {
                        if (!param.data.isValid)
                            continue;
                        auto extraInfoChild = &semantic.extraInfo(param.data);
                        if (param.data.nonterminalID == nonterminalIDFor!"InitializerClause")
                        {
                            currentRecordStart[!currentRecordStartI].entries.length
                                = currentRecordStart[currentRecordStartI].entries.length;
                            currentRecordStart[!currentRecordStartI].entries.toSlice[]
                                = currentRecordStart[currentRecordStartI].entries.toSlice[];

                            foreach (combination2; iterateCombinations())
                            {
                                IteratePPVersions ppVersion2 = IteratePPVersions(combination2, semantic.logicSystem,
                                    semantic.logicSystem.and(ppVersion.condition, param.condition),
                                    semantic.instanceCondition, semantic.mergedTreeDatas);
                                size_t start = currentRecordStart[currentRecordStartI].choose(
                                    ppVersion2);
                                while (start < recordFields.entries.length
                                    && !isInCorrectVersion(ppVersion2,
                                    recordFields.entries[start].condition))
                                    start++;

                                if (start < recordFields.entries.length)
                                {
                                    extraInfoChild.type = combineTypes(extraInfoChild.type,
                                        recordFields.entries[start].data.type2,
                                        null, ppVersion2.condition, semantic);

                                    start++;
                                }
                                currentRecordStart[!currentRecordStartI].addReplace(ppVersion2.condition,
                                    start, semantic.logicSystem, true);
                            }
                            currentRecordStartI = !currentRecordStartI;
                        }
                        else if (param.data.nonterminalID == nonterminalIDFor!"InitializerClauseDesignator")
                        {
                            assert(param.data.childs[0].nodeType == NodeType.array);
                            if (param.data.childs[0].childs.length == 1)
                            {
                                auto designator = param.data.childs[0].childs[0];
                                Declaration d;
                                foreach (f; recordFields.entries)
                                {
                                    if (f.data.name == designator.childs[1].content)
                                        d = f.data;
                                }
                                if (d !is null)
                                {
                                    extraInfoChild.referenced.add(semantic.logicSystem.and(ppVersion.condition,
                                        param.condition), d.declarationSet, semantic.logicSystem);
                                    extraInfoChild.type = combineTypes(extraInfoChild.type, d.type2, null,
                                        semantic.logicSystem.and(ppVersion.condition,
                                        param.condition), semantic);
                                }
                            }
                            else
                                writeln("TODO: InitializerClauseDesignator ",
                                    locationStr(tree.location));
                        }
                        else
                            writeln("TODO: ", param.data.name, " ", locationStr(tree.location));
                    }
                }
            }
        }

        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchNonterminals!("InitializerClause")) {
        if (realParent.name != "BracedInitList")
            updateType(extraInfoHere.type, semantic.extraInfo(realParent).type);
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
        if (realParent.name != "BracedInitList")
            updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[0]).type);
    }, (MatchNonterminals!("InitializerClauseDesignator")) {
        if (realParent.name != "BracedInitList")
            updateType(extraInfoHere.type, semantic.extraInfo(realParent).type);
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1] == q{"("} && !p.symbols[0].isToken)) {
        runSemantic(semantic, tree.childs[2], tree, condition);
        runSemantic(semantic, tree.childs[0], tree, condition);

        QualType functionType = semantic.extraInfo(tree.childs[0]).type;
        updateType(extraInfoHere.type, functionResultType(functionType, semantic));
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1].among(q{"->"}, q{"."}))) {
        //   | PostfixExpression "." "template"? IdExpression

        runSemantic(semantic, tree.childs[0], tree, condition);
        semantic.extraInfo(tree.childs[3]).contextType = semantic.extraInfo(tree.childs[0]).type;
        runSemantic(semantic, tree.childs[3], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[3]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "ClassOrDecltype" && symbolNames.length == 2)) {
        // NestedNameSpecifier? ClassName

        runSemantic(semantic, tree.childs[0], tree, condition);
        semantic.extraInfo(tree.childs[1]).contextType = semantic.extraInfo(tree.childs[0]).type;
        runSemantic(semantic, tree.childs[1], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[1]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "SimpleTypeSpecifierNoKeyword"
            && symbolNames.length == 2)) {
        // NestedNameSpecifier TypeName

        runSemantic(semantic, tree.childs[0], tree, condition);
        if (tree.childs[0].nonterminalID == nonterminalIDFor!"NestedNameSpecifier" && tree.childs[0].childs.length == 1)
            semantic.extraInfo(tree.childs[1])
                .contextType = QualType(semantic.getNamespaceType(null));
        else
            semantic.extraInfo(tree.childs[1]).contextType = semantic.extraInfo(tree.childs[0])
                .type;
        runSemantic(semantic, tree.childs[1], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[1]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "TypenameSpecifier")) {
        // = "typename" NestedNameSpecifier NameIdentifier
        // | "typename" NestedNameSpecifier "template"? SimpleTemplateId

        runSemantic(semantic, tree.childs[1], tree, condition);
        semantic.extraInfo(tree.childs[$ - 1]).contextType = semantic.extraInfo(tree.childs[1])
            .type;
        runSemantic(semantic, tree.childs[$ - 1], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[$ - 1]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "SimpleTemplateId")) {
        // TemplateName "<" TemplateArgumentList? ">"

        semantic.extraInfo(tree.childs[0]).contextType = semantic.extraInfo(tree).contextType;
        runSemantic(semantic, tree.childs[0], tree, condition);
        runSemantic(semantic, tree.childs[2], tree, condition);

        Tree parentX = realParent;
        while (parentX.isValid && parentX.nonterminalID.nonterminalIDAmong!("NestedNameSpecifier", "NestedNameSpecifierHead"))
            parentX = getRealParent(parentX, semantic);
        bool inDeclarator = parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"DeclaratorId";

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            QualType baseType = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);
            if (baseType.kind.among(TypeKind.record, TypeKind.typedef_))
            {
                auto t = cast(RecordType) baseType.type;

                Tree[] parameterExprs;
                bool hasNonterminal = false;
                iteratePPVersions!collectParameterExprs(tree.childs[2],
                    ppVersion, semantic, parameterExprs, hasNonterminal);
                QualType[] next;
                foreach (p; parameterExprs)
                    next ~= semantic.extraInfo(p).type;
                baseType = QualType(semantic.getRecordType(t.declarationSet,
                    next), baseType.qualifiers);

                Declaration[] realTemplateParameters;
                foreach (e; t.declarationSet.entries)
                {
                    if (e.data.type != DeclarationType.type)
                        continue;
                    if (!isInCorrectVersion(ppVersion, e.condition))
                        continue;
                    Tree classParent = getRealParent(e.data.tree, semantic);
                    if (classParent.isValid && classParent.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq")
                        classParent = getRealParent(classParent, semantic);
                    if (classParent.isValid && (classParent.name.canFind("SimpleDeclaration")
                        || classParent.name.canFind("MemberDeclaration")))
                        classParent = getRealParent(classParent, semantic);
                    if (!classParent.isValid || classParent.name != "TemplateDeclaration")
                        continue;

                    realTemplateParameters = [];

                    Tree[] templateParameterExprs;
                    bool hasNonterminal2 = false;
                    iteratePPVersions!collectParameterExprs(classParent.childs[2], ppVersion,
                        semantic, templateParameterExprs, hasNonterminal2);
                    foreach (p; templateParameterExprs)
                    {
                        Declaration paramDecl;
                        foreach (d; semantic.extraInfo(p).declarations)
                        {
                            if (d.type == DeclarationType.type)
                                paramDecl = d;
                        }
                        realTemplateParameters ~= paramDecl;
                    }
                }

                if (inDeclarator)
                {
                    foreach (i, p; parameterExprs)
                    {
                        if (p.nonterminalID == nonterminalIDFor!"TypeId"
                            && !p.childs[1].isValid
                            && p.childs[0].childs.length == 1
                            && p.childs[0].childs[0].nonterminalID == nonterminalIDFor!"NameIdentifier")
                        {
                            foreach (e; semantic.extraInfo(p.childs[0].childs[0])
                                .referenced.entries)
                            {
                                if (e.data.scope_.tree.isValid
                                    && e.data.scope_.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration")
                                {
                                    foreach (e2; e.data.entries)
                                    {
                                        auto condition2 = semantic.logicSystem.and(ppVersion.condition,
                                            semantic.logicSystem.and(e.condition, e2.condition));
                                        if (i < realTemplateParameters.length
                                            && realTemplateParameters[i]!is null)
                                            e2.data.realDeclaration.add(condition2,
                                                realTemplateParameters[i], semantic.logicSystem);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            combinedType = combineTypes(combinedType, baseType, null, condition, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "NestedNameSpecifier")) {
        foreach (i, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
        if (tree.childs.length >= 2)
            updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[$ - 2]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "NestedNameSpecifierHead")) {
        runSemantic(semantic, tree.childs[0], tree, condition);
        if (tree.childs[0].nonterminalID == nonterminalIDFor!"NestedNameSpecifier"
            && tree.childs[0].childs.length == 1)
            semantic.extraInfo(tree.childs[$ - 1])
                .contextType = QualType(semantic.getNamespaceType(null));
        else
            semantic.extraInfo(tree.childs[$ - 1])
                .contextType = semantic.extraInfo(tree.childs[0]).type;
        runSemantic(semantic, tree.childs[$ - 1], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[$ - 1]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "QualifiedId" && symbolNames.length == 3)) {
        // NestedNameSpecifier "template"? UnqualifiedId

        runSemantic(semantic, tree.childs[0], tree, condition);
        semantic.extraInfo(tree.childs[2]).contextType = semantic.extraInfo(tree.childs[0]).type;
        runSemantic(semantic, tree.childs[2], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[2]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "DecltypeSpecifier")) {
        runSemantic(semantic, tree.childs[2], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[2]).type);
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 4 && symbolNames[1] == q{"["} && symbolNames[3] == q{"]"})) {
        // PostfixExpression "[" Expression "]"
        // PostfixExpression "[" BracedInitList? "]"

        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            auto t = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);

            QualType t2;

            if (t.type !is null && t.kind.among(TypeKind.array, TypeKind.pointer))
                t2 = t.allNext()[0];

            combinedType = combineTypes(combinedType, t2, null, ppVersion.condition, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName == "PostfixExpression"
            && symbolNames.length == 2 && (symbolNames[1] == q{"++"} || symbolNames[1] == q{"--"}))) {
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[0]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "PrimaryExpression" && symbolNames.length == 3)) {
        assert(tree.childs[0].content == "(");
        assert(tree.childs[2].content == ")");

        runSemantic(semantic, tree.childs[1], tree, condition);
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[1]).type);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "ConditionalExpression")) {
        // LogicalOrExpression "?" Expression ":" AssignmentExpression

        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            auto type1 = chooseType(semantic.extraInfo(tree.childs[2]).type, ppVersion, true);
            auto type2 = chooseType(semantic.extraInfo(tree.childs[4]).type, ppVersion, true);

            if (type1.type !is null && type1.kind == TypeKind.array)
                type1 = QualType(semantic.getPointerType(type1.allNext()[0]), type1.qualifiers);
            if (type2.type !is null && type2.kind == TypeKind.array)
                type2 = QualType(semantic.getPointerType(type2.allNext()[0]), type2.qualifiers);

            QualType t2 = commonType(type1, type2, ppVersion, semantic);

            combinedType = combineTypes(combinedType, t2, null, ppVersion.condition, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "RelationalExpression")) {
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        extraInfoHere.type = QualType(semantic.getBuiltinType("bool"));
    }, (MatchNonterminals!("Literal")) {
        string value;
        assert(tree.childs[0].isToken, locationStr(tree.start));
        value = tree.childs[0].content;

        // https://en.cppreference.com/w/cpp/language/integer_literal

        bool isUnsigned;
        byte numLongs;

        foreach (char c; value)
        {
            if (c.inCharSet!"lL")
                numLongs++;
            if (c.inCharSet!"uU")
                isUnsigned = true;
        }

        string t;
        if (numLongs == 0)
        {
            if (isUnsigned)
                t = "unsigned";
            else
                t = "int";
        }
        else if (numLongs == 1)
        {
            if (isUnsigned)
                t = "unsigned_long";
            else
                t = "long";
        }
        else
        {
            if (isUnsigned)
                t = "unsigned_long_long";
            else
                t = "long_long";
        }
        extraInfoHere.type = QualType(semantic.getBuiltinType(t));
    }, (MatchNonterminals!("FloatLiteral")) {
        string value;
        assert(tree.childs[0].isToken, locationStr(tree.start));
        value = tree.childs[0].content;

        // https://en.cppreference.com/w/cpp/language/floating_literal

        byte numLongs;

        foreach (char c; value)
        {
            if (c.inCharSet!"lL")
                numLongs++;
        }

        if (numLongs)
            extraInfoHere.type = QualType(semantic.getBuiltinType("double"));
        else
            extraInfoHere.type = QualType(semantic.getBuiltinType("float"));
    }, (MatchNonterminals!("CharLiteral")) {
        string value;
        assert(tree.childs[0].isToken, locationStr(tree.start));
        value = tree.childs[0].content;

        // https://en.cppreference.com/w/cpp/language/character_literal

        Type charType = charTypeFromPrefix(value, semantic);

        extraInfoHere.type = QualType(charType);
    }, (MatchNonterminals!("BooleanLiteral")) {
        assert(tree.childs[0].isToken);
        extraInfoHere.type = QualType(semantic.getBuiltinType("bool"));
    }, (MatchNonterminals!("PointerLiteral")) {
        string value;
        assert(tree.childs[0].isToken);
        value = tree.childs[0].content;

        if (value.endsWith("nullptr"))
            extraInfoHere.type = QualType(semantic.getPointerType(
                QualType(semantic.getBuiltinType("__cppconv_bottom_t"))));
    }, (MatchNonterminals!("StringLiteral2")) {
        string value;
        assert(tree.childs[0].isToken);
        value = tree.childs[0].content;

        Type charType = charTypeFromPrefix(value, semantic);

        extraInfoHere.type = QualType(semantic.getArrayType(QualType(charType,
            Qualifiers.const_), Tree.init));
    }, (MatchNonterminals!("StringLiteralSequence")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        extraInfoHere.type = semantic.extraInfo(tree.childs[0].childs[0]).type;
    }, (MatchNonterminals!("LiteralS")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        extraInfoHere.type = semantic.extraInfo(tree.childs[0]).type;
    }, (MatchNonterminals!("TypeId")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            SimpleDeclarationInfo info;
            info.start = tree.start;
            info.tree = tree;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iterateTreeConditions!analyzeSimpleDeclaration(tree,
                ppVersion.condition, semantic, ppVersion, info);

            DeclaratorInfo declaratorInfo;

            QualType type = getDeclSpecType(semantic, info);

            iteratePPVersions!analyzeDeclarator(tree, ppVersion, semantic, declaratorInfo, type);

            if (declaratorInfo.type.type !is null)
                type = declaratorInfo.type;

            combinedType = combineTypes(combinedType, type, null, ppVersion.condition, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchNonterminals!("ConversionTypeId")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            SimpleDeclarationInfo info;
            info.start = tree.start;
            info.tree = tree;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iterateTreeConditions!analyzeSimpleDeclaration(tree,
                ppVersion.condition, semantic, ppVersion, info);

            DeclaratorInfo declaratorInfo;

            QualType type = getDeclSpecType(semantic, info);

            iteratePPVersions!analyzeDeclarator(tree, ppVersion, semantic, declaratorInfo, type);

            if (declaratorInfo.type.type !is null)
                type = declaratorInfo.type;

            combinedType = combineTypes(combinedType, type, null, ppVersion.condition, semantic);
        }

        updateType(extraInfoHere.type, combinedType);
    }, (MatchNonterminals!("CastExpressionHead")) {
        assert(tree.childs[0].content == "(");
        assert(tree.childs[2].content == ")");

        runSemantic(semantic, tree.childs[1], tree, condition);
        extraInfoHere.type = semantic.extraInfo(tree.childs[1]).type;
    }, (MatchNonterminals!("CastExpression", "CompoundLiteralExpression")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
            if (k == 0)
                extraInfoHere.type = semantic.extraInfo(tree.childs[0]).type;
        }
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "sizeof" && tree.childs.length == 4))) {
        // "sizeof" "(" TypeId ")"
        assert(tree.childs[1].content == "(");
        assert(tree.childs[3].content == ")");

        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        updateType(extraInfoHere.type, semantic.sizeType);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "sizeof" && tree.childs.length == 2))) {
        // "sizeof" UnaryExpression

        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        updateType(extraInfoHere.type, semantic.sizeType);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "__builtin_offsetof"))) {
        // "__builtin_offsetof" "(" TypeId "," Identifier ")"
        assert(tree.childs[1].content == "(");
        assert(tree.childs[5].content == ")");

        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            SimpleDeclarationInfo info;
            info.start = tree.start;
            info.tree = tree;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iterateTreeConditions!analyzeSimpleDeclaration(tree.childs[2],
                ppVersion.condition, semantic, ppVersion, info);

            DeclaratorInfo declaratorInfo;

            QualType type = getDeclSpecType(semantic, info);
            QualType declaredType;

            iteratePPVersions!analyzeDeclarator(tree.childs[2], ppVersion,
                semantic, declaratorInfo, type);

            if (declaratorInfo.type.type !is null)
                type = declaratorInfo.type;

            combinedType = combineTypes(combinedType, type, null, ppVersion.condition, semantic);
        }

        updateType(semantic.extraInfo(tree.childs[2]).type, combinedType);
        updateType(extraInfoHere.type, semantic.sizeType);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content == "__builtin_va_arg"))) {
        // "__builtin_va_arg" "(" Expression "," TypeId ")"
        assert(tree.childs[1].content == "(");
        assert(tree.childs[5].content == ")");

        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        size_t i;
        foreach (combination; iterateCombinations())
        {
            SimpleDeclarationInfo info;
            info.start = tree.start;
            info.tree = tree;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iterateTreeConditions!analyzeSimpleDeclaration(tree.childs[4],
                ppVersion.condition, semantic, ppVersion, info);

            DeclaratorInfo declaratorInfo;

            QualType type = getDeclSpecType(semantic, info);
            QualType declaredType;

            iteratePPVersions!analyzeDeclarator(tree.childs[4], ppVersion,
                semantic, declaratorInfo, type);

            if (declaratorInfo.type.type !is null)
                type = declaratorInfo.type;

            combinedType = combineTypes(combinedType, type, null, ppVersion.condition, semantic);
        }

        updateType(semantic.extraInfo(tree.childs[4]).type, combinedType);
        updateType(extraInfoHere.type, semantic.sizeType);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("-", "+", "~") && tree.childs.length == 2))) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[1]).type);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("&") && tree.childs.length == 2))) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            auto t = chooseType(semantic.extraInfo(tree.childs[1]).type, ppVersion, false);
            if (t.kind == TypeKind.reference)
                t = chooseType(t.allNext()[0], ppVersion, false).withExtraQualifiers(t.qualifiers);

            QualType result;
            result = QualType(semantic.getPointerType(t));

            combinedType = combineTypes(combinedType, result, null, ppVersion.condition, semantic);
        }
        updateType(extraInfoHere.type, combinedType);
    }, (MatchNonterminals!("UnaryExpression"),
            MatchFunc!(() => (tree.childs[0].content.among("*") && tree.childs.length == 2))) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            auto t = chooseType(semantic.extraInfo(tree.childs[1]).type, ppVersion, true);
            if (t.kind == TypeKind.reference)
                t = chooseType(t.allNext()[0], ppVersion, true).withExtraQualifiers(t.qualifiers);

            if (t.type !is null && t.kind == TypeKind.array)
                t = QualType(semantic.getPointerType(t.allNext()[0]), t.qualifiers);

            QualType result;
            if (t.type !is null && t.kind.among(TypeKind.array, TypeKind.pointer))
                result = t.allNext()[0];

            combinedType = combineTypes(combinedType, result, null, ppVersion.condition, semantic);
        }
        updateType(extraInfoHere.type, combinedType);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "JumpStatement2" && symbolNames[0] == q{"return"})) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("IfStatement", "ElseIfStatement", "ElseStatement", "SwitchStatement"))) {
        SemanticRunInfo semanticRun = semantic;
        if (tree !in semantic.currentScope.childScopeByTree)
        {
            semantic.currentScope.childScopeByTree[tree] = createScope(tree,
                semantic.currentScope, instanceConditionHere, semantic.logicSystem);
        }
        semanticRun.currentScope = semantic.currentScope.childScopeByTree[tree];

        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName == "IterationStatement")) {
        SemanticRunInfo semanticRun = semantic;
        if (tree !in semantic.currentScope.childScopeByTree)
        {
            semantic.currentScope.childScopeByTree[tree] = createScope(tree,
                semantic.currentScope, instanceConditionHere, semantic.logicSystem);
        }
        semanticRun.currentScope = semantic.currentScope.childScopeByTree[tree];

        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchNonterminals!("AssignmentExpression")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        updateType(extraInfoHere.type, semantic.extraInfo(tree.childs[0]).type);
    }, (MatchNonterminals!("EqualityExpression")) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        updateType(extraInfoHere.type, QualType(semantic.getBuiltinType("bool")));
    }, (MatchProductions!((p, nonterminalName, symbolNames) => nonterminalName.among("MultiplicativeExpression", "AdditiveExpression",
            "AndExpression", "InclusiveOrExpression", "ExclusiveOrExpression", "AndExpression"))) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        auto t1 = semantic.extraInfo(tree.childs[0]).type;
        auto t2 = semantic.extraInfo(tree.childs[2]).type;

        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                condition, semantic.instanceCondition, semantic.mergedTreeDatas);

            auto lhs = chooseType(t1, ppVersion, true);
            auto rhs = chooseType(t2, ppVersion, true);

            if (lhs.type !is null && lhs.kind == TypeKind.array)
                lhs = QualType(semantic.getPointerType((cast(ArrayType) lhs.type)
                    .next), lhs.qualifiers);
            if (rhs.type !is null && rhs.kind == TypeKind.array)
                rhs = QualType(semantic.getPointerType((cast(ArrayType) rhs.type)
                    .next), rhs.qualifiers);

            QualType result = lhs;

            if (lhs.type !is null && rhs.type !is null
                && lhs.kind == TypeKind.record && rhs.kind == TypeKind.builtin)
            {
                result = rhs;
            }

            if (lhs.type !is null && rhs.type !is null
                && lhs.kind == TypeKind.builtin && rhs.kind == TypeKind.builtin)
            {
                auto lhs2 = cast(BuiltinType) lhs.type;
                auto rhs2 = cast(BuiltinType) rhs.type;

                auto lhsInfo = getIntegralInfo(lhs2.name);
                auto rhsInfo = getIntegralInfo(rhs2.name);

                if (rhsInfo.sizeOrder > lhsInfo.sizeOrder)
                    result = rhs;

                if (lhsInfo.sizeOrder < getIntegralInfo("int").sizeOrder
                    && rhsInfo.sizeOrder < getIntegralInfo("int").sizeOrder)
                {
                    if (lhsInfo.isUnsigned)
                    {
                        result = QualType(semantic.getBuiltinType("unsigned"), lhs.qualifiers);
                    }
                    else
                    {
                        result = QualType(semantic.getBuiltinType("int"), lhs.qualifiers);
                    }
                }
            }

            if (tree.childs[1].content == "-" && lhs.type !is null
                && rhs.type !is null && lhs.kind == TypeKind.pointer && rhs.kind == TypeKind.pointer)
                result = semantic.sizeType;

            combinedType = combineTypes(combinedType, result, null, ppVersion.condition, semantic);
        }
        updateType(extraInfoHere.type, combinedType);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("ShiftExpression"))) {
        foreach (k, ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }

        auto t1 = semantic.extraInfo(tree.childs[0]).type;

        updateType(extraInfoHere.type, t1);
    }, (MatchProductions!((p, nonterminalName,
            symbolNames) => nonterminalName.among("CompoundStatement"))) {
        SemanticRunInfo semanticRun = semantic;
        if (tree !in semantic.currentScope.childScopeByTree)
        {
            semantic.currentScope.childScopeByTree[tree] = createScope(tree,
                semantic.currentScope, instanceConditionHere, semantic.logicSystem);
        }
        semanticRun.currentScope = semantic.currentScope.childScopeByTree[tree];

        foreach (ref c; tree.childs)
        {
            runSemantic(semanticRun, c, tree, condition);
        }
    }, (MatchProductionId!(INCLUDE_TREE_PRODUCTION_ID)) {
        if (semantic.mergedFileByName)
        {
            RealFilename filename = RealFilename(tree.childs[0].content);
            auto nextFile = stackLocations(semantic.currentFile,
                semantic.locationContextMap.getLocationContext(immutable(LocationContext)(tree.start.context,
                tree.start.loc, tree.inputLength, "", filename.name, false)),
                semantic.locationContextMap);
            if (filename !in semantic.mergedFileByName)
                return;
            runSemanticFile(semantic, nextFile);
        }
    }, () {
        foreach (ref c; tree.childs)
        {
            runSemantic(semantic, c, tree, condition);
        }
    }); //(tree, realParent);

    mixin(generateMatchTreeCode!Funcs());
}

void runSemanticFile(SemanticRunInfo semantic, immutable(LocationContext*) nextFile)
{
    auto mergedFile = semantic.mergedFileByName[RealFilename(nextFile.filename)];
    if (nextFile !in mergedFile.locPrefixToInstance)
        return;
    auto instanceId = mergedFile.locPrefixToInstance[nextFile];
    if (!mergedFile.instances[instanceId].hasTree)
        return;
    semantic.currentFile = nextFile;
    semantic.instanceCondition = mergedFile.instances[instanceId].instanceCondition;

    auto instanceCondition2 = semantic.logicSystem.and(mergedFile.instances[instanceId].instanceCondition,
            mergedFile.instances[instanceId].instanceConditionUsed);

    auto savedTreesVisited = semantic.treesVisited;
    semantic.treesVisited = null;
    foreach (t; mergedFile.mergedTrees)
        runSemantic(semantic, t, Tree.init, mergedFile.instances[instanceId].instanceConditionUsed /*instanceCondition2*/ );

    semantic.treesVisited = savedTreesVisited;
}
