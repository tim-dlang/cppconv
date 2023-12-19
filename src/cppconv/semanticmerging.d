
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.semanticmerging;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppparallelparser;
import cppconv.cppparserwrapper;
import cppconv.cppsemantic;
import cppconv.cpptree;
import cppconv.cpptype;
import cppconv.filecache;
import cppconv.locationstack;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.stdio;

struct MergeFilesData2
{
    Semantic mergedSemantic;

    Declaration[Declaration] getTargetDeclarationCache;
    Declaration getTargetDeclaration(Declaration sourceDecl)
    {
        auto cacheEntry = sourceDecl in getTargetDeclarationCache;
        if (cacheEntry)
            return *cacheEntry;
        Tree tree = sourceDecl.tree;
        Tree declaratorTree = sourceDecl.declaratorTree;
        DeclarationKey key;

        key.type = sourceDecl.type;
        key.tree = tree;
        key.declaratorTree = declaratorTree;
        key.flags = sourceDecl.flags;
        key.bitfieldSize = sourceDecl.bitfieldSize;
        assert(sourceDecl.scope_ !is null);
        key.scope_ = getTargetScope(sourceDecl.scope_);
        key.name = sourceDecl.declarationSet.name;

        Declaration d;

        auto declInMap = key in mergedSemantic.declarationCache;
        if (declInMap)
        {
            d = *declInMap;
            getTargetDeclarationCache[sourceDecl] = d;
            assert(d.tree is tree);
            assert(d.declaratorTree is declaratorTree);
            assert(d.type == sourceDecl.type);
            assert(d.flags == sourceDecl.flags);
            auto condition2 = /*mergedSemantic.logicSystem.rebuiltFormula*/ (sourceDecl.condition); //mergedSemantic.logicSystem.and(sourceDecl.condition, mergedFile.instances[instanceId].instanceCondition);
            d.type2 = combineTypes(d.type2, mapType(sourceDecl.type2), null,
                    condition2, mergedSemantic);
            d.condition = mergedSemantic.logicSystem.or(condition2, d.condition);
            d.declarationSet.updateCondition(d, d.condition,
                    mergedSemantic.logicSystem, sourceDecl.isRedundant);
        }
        else
        {
            d = new Declaration;
            mergedSemantic.declarationCache[key] = d;
            getTargetDeclarationCache[sourceDecl] = d;
            d.key = key;
            auto condition2 = /*mergedSemantic.logicSystem.rebuiltFormula*/ (sourceDecl.condition); //mergedSemantic.logicSystem.and(sourceDecl.condition, mergedFile.instances[instanceId].instanceCondition);
            d.condition = condition2;
            d.location = sourceDecl.location; //removeLocationPrefix(sourceDecl.location, fileInstanceInfo.instanceLocations[instanceId].prev, mergedSemantic.locationContextMap);
            if (!sourceDecl.declarationSet.outsideSymbolTable)
            {
                d.declarationSet = key.scope_.getDeclarationSet(sourceDecl.name,
                        mergedSemantic.logicSystem);
                d.declarationSet.addNew(d, mergedSemantic.logicSystem, sourceDecl.isRedundant);
            }
            else
            {
                auto ds = new DeclarationSet(sourceDecl.name, key.scope_);
                ds.outsideSymbolTable = true;
                ds.addNew(d, mergedSemantic.logicSystem, sourceDecl.isRedundant);
            }
            d.type2 = combineTypes(QualType(), mapType(sourceDecl.type2), null,
                    condition2, mergedSemantic);
        }

        foreach (e; sourceDecl.realDeclaration.entries)
        {
            assert(mergedSemantic.logicSystem.and(e.condition, e.data.condition.negated)
                    .isFalse, text("adding real decl for ", sourceDecl.name, " ",
                        locationStr(sourceDecl.location), " ", locationStr(e.data.location), " ",
                        e.condition.toString, " ", e.data.condition.toString));
            d.realDeclaration.add(/*mergedSemantic.logicSystem.rebuiltFormula*/
                    (e.condition), //mergedSemantic.logicSystem.and(mergedFile.instances[instanceId].instanceCondition, e.condition),
                    getTargetDeclaration(e.data),
                    mergedSemantic.logicSystem);
        }

        foreach (e; sourceDecl.bitFieldInfo.entries)
        {
            d.bitFieldInfo.add(e.condition /*mergedSemantic.logicSystem.and(e.condition, mergedFile.instances[instanceId].instanceCondition)*/ ,
                    e.data, mergedSemantic.logicSystem);
        }

        return d;
    }

    void translateScopeExtraParents(Scope s, Scope r)
    {
        size_t startIndex = 0;
        foreach (e; s.extraParentScopes.entries)
        {
            startIndex = r.extraParentScopes.add(e.condition, ExtraScope(e.data.type,
                    getTargetScope(e.data.scope_)), mergedSemantic.logicSystem, startIndex) + 1;
        }
    }

    Scope getTargetScope(Scope s)
    {
        Tree tree = s.tree;

        if (s.parentScope !is null)
        {
            Scope parentScope = getTargetScope(s.parentScope);

            if (!tree.isValid)
            {
                if (s.className.entries.length != 1)
                {
                    writeln("s.className.entries ", s.className.entries.length, " ", s.toString);
                    foreach (e; s.className.entries)
                        writeln("  ", e.data, " ", e.condition.toString);
                }
                assert(s.className.entries.length == 1);
                auto nameInNamespaces = s.className.entries[0].data in parentScope.childNamespaces;
                if (nameInNamespaces)
                {
                    (*nameInNamespaces).scopeCondition = mergedSemantic.logicSystem.or((*nameInNamespaces)
                            .scopeCondition, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                                s.scopeCondition));
                    translateScopeExtraParents(s, *nameInNamespaces);
                    return *nameInNamespaces;
                }
                else
                {
                    Scope s2 = new Scope(tree, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                                s.scopeCondition));
                    s2.parentScope = parentScope;
                    s2.parentScope.childNamespaces[s.className.entries[0].data] = s2;
                    foreach (e; s.className.entries)
                        s2.className.add(e.condition, e.data, mergedSemantic.logicSystem);
                    translateScopeExtraParents(s, s2);
                    return s2;
                }
            }
            else
            {
                auto treeInChildScopes = tree in parentScope.childScopeByTree;
                if (treeInChildScopes)
                {
                    (*treeInChildScopes).scopeCondition = mergedSemantic.logicSystem.or((*treeInChildScopes)
                            .scopeCondition, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                                s.scopeCondition));
                    translateScopeExtraParents(s, *treeInChildScopes);
                    return *treeInChildScopes;
                }
                else
                {
                    Scope s2 = new Scope(tree, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                                s.scopeCondition));
                    s2.parentScope = parentScope;
                    s2.parentScope.childScopeByTree[tree] = s2;
                    translateScopeExtraParents(s, s2);
                    return s2;
                }
            }
        }
        else
        {
            assert(s.extraParentScopes.entries.length == 0);
            if (mergedSemantic.rootScope is null)
            {
                mergedSemantic.rootScope = new Scope(tree, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                            s.scopeCondition));
            }
            else
            {
                mergedSemantic.rootScope.scopeCondition = mergedSemantic.logicSystem.or(
                        mergedSemantic.rootScope.scopeCondition, /*mergedSemantic.logicSystem.rebuiltFormula*/ (
                            s.scopeCondition));
            }
            return mergedSemantic.rootScope;
        }
    }

    DeclarationSet getTargetDeclarationSet(DeclarationSet sourceSet)
    {
        if (!sourceSet.outsideSymbolTable)
        {
            auto s = getTargetScope(sourceSet.scope_);
            auto declInSymbols = sourceSet.name in s.symbols;
            if (declInSymbols)
            {
                return *declInSymbols;
            }
            auto ds = new DeclarationSet(sourceSet.name, s);
            s.symbols[sourceSet.name] = ds;
            foreach (e; sourceSet.entries)
            {
                if (e.data.type != DeclarationType.forwardScope)
                    getTargetDeclaration(e.data);
            }
            return ds;
        }
        else
        {
            assert(sourceSet.entries.length == 1);
            auto d = getTargetDeclaration(sourceSet.entries[0].data);
            assert(d.declarationSet.entries.length == 1);
            assert(d.declarationSet.entries[0].data is d);
            return d.declarationSet;
        }
    }

    static string genMapTypeCode()
    {
        string code;
        foreach (kind; __traits(allMembers, TypeKind)[1 .. $])
        {
            enum kindU = () {
                string r = (kind[0] - 'a' + 'A') ~ kind[1 .. $];
                if (r[$ - 1] == '_')
                    r = r[0 .. $ - 1];
                return r;
            }();

            mixin("alias T = " ~ kindU ~ "Type;");

            code ~= "        if (type.kind == TypeKind." ~ kind ~ ")\n";
            code ~= "        {\n";
            code ~= "            " ~ kindU ~ "Type type2 = cast(" ~ kindU ~ "Type)type;\n";
            code ~= "            return mergedSemantic.get" ~ kindU ~ "Type(";
            foreach (name; FieldNameTupleAll!T)
            {
                alias T2 = typeof(__traits(getMember, T, name));
                static if (is(T2 == string))
                    code ~= "type2." ~ name ~ ", ";
                else static if (is(T2 == Declaration))
                    code ~= "getTargetDeclaration(type2." ~ name ~ "), ";
                else static if (is(T2 == QualType))
                    code ~= "mapType(type2." ~ name ~ "), ";
                else static if (is(T2 == QualType[]))
                    code ~= "mapType(type2." ~ name ~ "), ";
                else static if (is(T2 == Tree))
                    code ~= "type2." ~ name ~ ", ";
                else static if (is(T2 == bool))
                    code ~= "type2." ~ name ~ ", ";
                else static if (is(T2 == size_t))
                    code ~= "type2." ~ name ~ ", ";
                else static if (is(T2 == immutable(Formula*)[]))
                    code ~= "/*rebuiltFormulas*/(type2." ~ name ~ "), ";
                else static if (is(T2 == Scope))
                    code ~= "getTargetScope(type2." ~ name ~ "), ";
                else static if (is(T2 == DeclarationSet))
                    code ~= "getTargetDeclarationSet(type2." ~ name ~ "), ";
                else
                    static assert(false);
            }
            code ~= ")";
            if (kindU == "Condition")
                code ~= ".type";
            code ~= ";\n";
            code ~= "        }\n";
        }
        return code;
    }

    Type mapType(Type type)
    {
        if (type is null)
            return null;
        mixin(genMapTypeCode());
        assert(false);
    }

    QualType mapType(QualType type)
    {
        return QualType(mapType(type.type), type.qualifiers);
    }

    QualType[] mapType(QualType[] types)
    {
        QualType[] r;
        r.length = types.length;
        foreach (i; 0 .. types.length)
            r[i] = mapType(types[i]);
        return r;
    }
}

void mergeSemantics(Semantic mergedSemantic, Semantic semantic2,
        RealFilename[] inputFilesHere, MergedFile[] mergedFiles)
{
    auto logicSystem = mergedSemantic.logicSystem;
    MergeFilesData2 mergeFilesData;
    mergeFilesData.mergedSemantic = mergedSemantic;

    if (mergedSemantic.rootScope is null)
        mergedSemantic.rootScope = mergeFilesData.getTargetScope(semantic2.rootScope);
    else
        assert(mergedSemantic.rootScope is mergeFilesData.getTargetScope(semantic2.rootScope));
    mergedSemantic.rootScope.initialized = true;

    foreach (name, origDs; semantic2.rootScope.symbols)
    {
        auto nameInSymbols = name in mergedSemantic.rootScope.symbols;
        DeclarationSet mergedDs;
        if (nameInSymbols)
        {
            mergedDs = *nameInSymbols;
        }
        else
        {
            mergedDs = new DeclarationSet(name, mergedSemantic.rootScope);
            mergedSemantic.rootScope.symbols[name] = mergedDs;
        }
        foreach (e; origDs.entries)
        {
            if (e.data.type != DeclarationType.forwardScope)
                mergeFilesData.getTargetDeclaration(e.data);
        }
    }

    void translateScope(Scope s)
    {
        mergeFilesData.getTargetScope(s);
        foreach (t, s2; s.childScopeByTree)
            translateScope(s2);
    }

    translateScope(semantic2.rootScope);

    foreach (ref sortedFile; mergedFiles)
    {
        auto startTime = MonoTimeImpl!(ClockType.threadCPUTime).currTime;
        immutable(Formula)* combinedInstanceCondition = mergedSemantic.logicSystem.false_;
        immutable(Formula)* combinedInstanceConditionUsed = mergedSemantic.logicSystem.false_;
        size_t numInstances;
        foreach_reverse (instance; sortedFile.instances)
        {
            if (instance.instanceCondition is null)
                continue;
            if (inputFilesHere.canFind(instance.tuFile) || !numInstances)
            {
                combinedInstanceCondition = mergedSemantic.logicSystem.or(combinedInstanceCondition,
                        instance.instanceCondition);
            }
            if (inputFilesHere.canFind(instance.tuFile))
            {
                combinedInstanceConditionUsed = mergedSemantic.logicSystem.or(
                        combinedInstanceConditionUsed, instance.instanceConditionUsed);
                numInstances++;
            }
        }
        if (numInstances == 0)
            continue;
        void mergeSemantic(Tree tree, Tree parent, immutable(Formula)* treeCondition)
        {
            if (!tree.isValid)
                return;
            if (tree !in semantic2.treeToID)
                return;

            MergedTreeData* mdata;
            if (tree.nodeType == NodeType.merged)
            {
                mdata = &mergedSemantic.mergedTreeData(tree);
                auto mdata2 = &semantic2.mergedTreeData(tree);

                foreach (i; 0 .. mdata.conditions.length)
                {
                    mdata.conditions[i] = logicSystem.or(mdata.conditions[i], /*logicSystem.rebuiltFormula*/ (
                                mdata2.conditions[i]));
                }
                mdata.mergedCondition = logicSystem.or(mdata.mergedCondition, /*logicSystem.rebuiltFormula*/ (
                            mdata2.mergedCondition));
            }

            foreach (i; 0 .. tree.childs.length)
            {
                immutable(Formula)* treeCondition2 = treeCondition;
                if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
                {
                    ConditionTree ctree = tree.toConditionTree;
                    treeCondition2 = logicSystem.and(treeCondition, ctree.conditions[i]);
                }
                else if (mdata !is null)
                    treeCondition2 = logicSystem.and(treeCondition,
                            logicSystem.or(mdata.conditions[i], mdata.mergedCondition));
                mergeSemantic(tree.childs[i], tree, treeCondition2);
            }

            auto startTime = MonoTimeImpl!(ClockType.threadCPUTime).currTime;

            auto targetExtraInfo = &mergedSemantic.extraInfo(tree);
            auto sourceExtraInfo = &semantic2.extraInfo(tree);

            if (tree.nodeType == NodeType.array)
                return;

            if (!tree.nameOrContent.startsWith("@#IncludeDecl"))
                targetExtraInfo.sourceTrees += numInstances;

            QualType mapType(QualType t)
            {
                return filterType(mergeFilesData.mapType(t),
                        logicSystem.and(combinedInstanceConditionUsed,
                            treeCondition), mergedSemantic);
            }

            targetExtraInfo.type = combineTypes(targetExtraInfo.type,
                    mapType(sourceExtraInfo.type), null,
                    combinedInstanceCondition, mergedSemantic);
            mergeConditionMaps!(x => mergeFilesData.getTargetDeclarationSet(x))(
                    targetExtraInfo.referenced, sourceExtraInfo.referenced,
                    combinedInstanceCondition, combinedInstanceConditionUsed, logicSystem);
            foreach (d; sourceExtraInfo.declarations)
            {
                targetExtraInfo.declarations.addOnce(mergeFilesData.getTargetDeclaration(d));
            }
        }

        Tree[] mergedTrees = sortedFile.mergedTrees;

        foreach (tree; mergedTrees)
        {
            mergeSemantic(tree, Tree.init, logicSystem.true_);
        }
    }

    mergeFilesData.getTargetDeclarationCache.clear();
    destroy(mergeFilesData);
}
