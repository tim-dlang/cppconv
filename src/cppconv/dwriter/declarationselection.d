
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter.declarationselection;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.dwriter.declarationcode;
import cppconv.dwriter.macrodeclaration;
import cppconv.dwriter.dwriter;
import cppconv.filecache;
import cppconv.grammarcpp;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import cppconv.utils;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.typecons;

alias TypedefType = cppconv.cppsemantic.TypedefType;

bool isTypeBlacklisted(DWriterData data, QualType t)
{
    if (t.type is null)
        return false;
    if (t.kind == TypeKind.reference)
        t = t.allNext()[0];
    if (t.kind == TypeKind.rValueReference)
        return true;
    if (t.name == "initializer_list")
        return true;
    if (t.kind == TypeKind.typedef_)
    {
        RecordType recordType = cast(RecordType) t.type;
        Scope s = recordType.declarationSet.scope_;
        if (s.className.entries.length && s.className.entries[0].data == "chrono")
            return true;
    }
    if (t.kind == TypeKind.record)
    {
        RecordType recordType = cast(RecordType) t.type;
        Scope s = recordType.declarationSet.scope_;
        while (s.parentScope !is null && s.parentScope.parentScope !is null)
            s = s.parentScope;
        if (s.className.entries.length && s.className.entries[0].data == "std")
            return true;
    }
    return false;
}

bool isDeclarationBlacklisted(DWriterData data, Declaration d)
{
    auto inCache = d in data.blacklistedCache;
    if (inCache)
        return *inCache;
    bool r = isDeclarationBlacklistedImpl(data, d);
    data.blacklistedCache[d] = r;
    return r;
}

bool isDeclarationBlacklistedImpl(DWriterData data, Declaration d)
{
    if (d.location.context is null)
        return false;
    if (d.type == DeclarationType.varOrFunc && (d.flags & DeclarationFlags.function_) == 0
            && (d.flags & DeclarationFlags.static_) == 0 && !isRootNamespaceScope(d.scope_))
        return false;
    if ((d.flags & DeclarationFlags.virtual) || (d.flags & DeclarationFlags.override_))
        return false;
    if (d.flags & DeclarationFlags.friend)
        return true;
    if (d.flags & DeclarationFlags.templateSpecialization)
        return true;

    if (d.type == DeclarationType.varOrFunc
            && d.tree.name.startsWith("FunctionDefinition")
            && d.tree.childs.length == 4 && d.tree.childs[2].content.among( /*"delete",*/ "default"))
        return true;

    if (d.name.startsWith("emplace", "insertOne"))
        return false;

    QualType type = d.type2;
    if (type.kind == TypeKind.condition)
    {
        auto conditionType = cast(ConditionType) type.type;
        if (conditionType.conditions.length == 1)
            type = conditionType.types[0];
    }

    if (type.kind == TypeKind.function_)
    {
        auto functionType = cast(FunctionType) type.type;
        if (functionType.functionQualifiers & FunctionQualifiers.rValueRef)
            return true;
        foreach (p; functionType.parameters)
        {
            if (isTypeBlacklisted(data, p))
                return true;
            QualType p2 = p;
            if (p2.kind == TypeKind.reference)
                p2 = p2.allNext()[0];
            if (d.name.among("operator <<", "operator >>") && p2.type !is null
                    && p2.name.among("QDebug", "QDataStream", "QTextStream"))
                return true;
        }
        if (isTypeBlacklisted(data, functionType.resultType))
            return true;
    }

    foreach_reverse (ref pattern; data.options.blacklist)
    {
        DeclarationMatch match;
        if (isDeclarationMatch(pattern, match, d, data.semantic))
            return true;
    }
    return false;
}

struct DependencyInfo
{
    immutable(Formula)* condition;
    bool outsideFunction;
    bool outsideMixin;
    LocationX locAdded;
}

DependencyInfo[Declaration] getDeclDependencies(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;

    if (d.type == DeclarationType.forwardScope)
        return null;

    static DependencyInfo[Declaration][Declaration] cache;
    if (d in cache)
        return cache[d];

    DependencyInfo[Declaration] r;
    void add2(Declaration d2, immutable(Formula)* condition,
            bool outsideFunction, bool outsideMixin, LocationX locAdded)
    {
        if (isDeclarationBlacklisted(data, d2))
            return;
        if (d2.type == DeclarationType.namespace)
            return;
        if (d2.type == DeclarationType.macroParam)
            return;
        if (condition.isFalse)
            return;
        auto x = d2 in r;
        if (x)
            *x = DependencyInfo(semantic.logicSystem.or((*x).condition, condition),
                    (*x).outsideFunction || outsideFunction, (*x)
                        .outsideMixin || outsideMixin, (*x).locAdded);
        else
            r[d2] = DependencyInfo(condition, outsideFunction, outsideMixin, locAdded);
    }

    void add(Declaration d2, immutable(Formula)* condition, bool outsideFunction,
            bool outsideMixin, LocationX locAdded)
    {
        LocationRangeX loc1 = d.location;
        if (d.tree.isValid)
            loc1 = d.tree.location;
        LocationRangeX loc2 = d2.location;
        if (d2.tree.isValid)
            loc2 = d2.tree.location;
        if (d2.type == DeclarationType.type || (d.type != DeclarationType.macro_
                && d2.type == DeclarationType.varOrFunc && (d2.flags & DeclarationFlags.static_) != 0))
        {
            if (!hasCommonParentScope(d.scope_, d2.scope_))
            {
                auto conditionReachable = locationReachable(loc1, loc2, data);
                condition = semantic.logicSystem.and(condition, conditionReachable);
                if (conditionReachable.isFalse)
                {
                    return;
                }
            }
        }

        if (d2.type == DeclarationType.type
                && (d2.flags & DeclarationFlags.typedef_) != 0
                && isSelfTypedef(d2, data))
        {
            Declaration d3 = getSelfTypedefTarget(d2, data);
            if (d3 !is null && d3.type != DeclarationType.builtin)
                d2 = d3;
            else
                return;
        }

        immutable(Formula)* conditionLeft = condition;
        foreach (e; d2.realDeclaration.entries)
        {
            add2(e.data, semantic.logicSystem.and(e.condition, condition),
                    outsideFunction, outsideMixin, locAdded);
            conditionLeft = semantic.logicSystem.and(conditionLeft, e.condition.negated);
        }
        add2(d2, conditionLeft, outsideFunction, outsideMixin, locAdded);
    }

    void visitType(QualType type, immutable(Formula)* condition,
            bool outsideFunction, bool outsideMixin, LocationX locAdded)
    {
        if (type.type is null)
            return;
        if (type.kind == TypeKind.condition)
        {
            auto ctype = cast(ConditionType) type.type;
            foreach (i, x; ctype.types)
            {
                visitType(x, semantic.logicSystem.and(condition,
                        ctype.conditions[i]), outsideFunction, outsideMixin, locAdded);
            }
        }
        else if (type.kind == TypeKind.record)
        {
            RecordType recordType = cast(RecordType) type.type;
            if (recordType.declarationSet.scope_.isRootNamespaceScope)
                foreach (e; recordType.declarationSet.entries)
                {
                    if (e.data.type != DeclarationType.type)
                        continue;
                    if ((e.data.flags & DeclarationFlags.typedef_) != 0)
                        continue;
                    if (isDeclarationBlacklisted(data, e.data))
                        continue;
                    add(e.data, semantic.logicSystem.and(condition,
                            e.condition), outsideFunction, outsideMixin, locAdded);
                }
        }
        else if (type.kind == TypeKind.typedef_)
        {
            TypedefType typedefType = cast(TypedefType) type.type;
            bool blacklisted = false;
            if (typedefType.declarationSet !is null)
            {
                blacklisted = true;
                foreach (e; typedefType.declarationSet.entries)
                    if (!isDeclarationBlacklisted(data, e.data))
                        blacklisted = false;

                if (typedefType.declarationSet.scope_.isRootNamespaceScope)
                    foreach (e; typedefType.declarationSet.entries)
                    {
                        if (e.data.type != DeclarationType.type)
                            continue;
                        if ((e.data.flags & DeclarationFlags.typedef_) == 0)
                            continue;
                        if (isDeclarationBlacklisted(data, e.data))
                            continue;
                        add(e.data, semantic.logicSystem.and(condition,
                                e.condition), outsideFunction, outsideMixin, locAdded);
                    }
            }
        }
        else if (type.kind == TypeKind.builtin)
        {
            if (data.options.builtinCppTypes)
            {
                string translation;
                switch (type.name)
                {
                case "long":
                    translation = "cpp_long";
                    break;
                case "unsigned_long":
                    translation = "cpp_ulong";
                    break;
                case "long_long":
                    translation = "cpp_longlong";
                    break;
                case "unsigned_long_long":
                    translation = "cpp_ulonglong";
                    break;
                default:
                }
                if (translation.length)
                    add(data.dummyDeclaration(translation, "core.stdc.config"),
                            condition, outsideFunction, outsideMixin, locAdded);
            }
        }
        else
        {
            foreach (x; type.allNext())
                visitType(x, condition, outsideFunction, outsideMixin, locAdded);
        }
    }

    enum Flags
    {
        none = 0,
        addNormal = 1,
        addInterpolatMixins = 2,
        all = addNormal | addInterpolatMixins,
        inTemplate = 4
    }

    bool[Tree][MacroDeclarationInstance] macroDone;

    void visitTree(Tree tree, immutable(Formula)* condition, Flags flags,
            MacroDeclarationInstance currentMacroInstance, bool outsideFunction, bool outsideMixin)
    {
        if (!tree.isValid)
            return;
        if (tree.nameOrContent == "FunctionBody")
            outsideFunction = false;
        Tree parent = getRealParent(tree, semantic);
        if (currentMacroInstance)
        {
            if (currentMacroInstance in macroDone && tree in macroDone[currentMacroInstance])
                return;
            macroDone[currentMacroInstance][tree] = true;
        }
        if (tree in data.macroReplacement)
        {
            bool foundThisMacro;
            bool isValueMacro;
            bool isMixinMacro;
            bool isMacroParam;
            bool hasSubMacros;
            void onDep(MacroDeclarationInstance instance2)
            {
                if (instance2 is currentMacroInstance)
                {
                    foundThisMacro = true;
                    foreach (x; instance2.extraDeps)
                    {
                        onDep(x);
                    }
                    foundThisMacro = false;
                    return;
                }
                if (currentMacroInstance !is null && !foundThisMacro)
                {
                    foreach (x; instance2.extraDeps)
                    {
                        onDep(x);
                    }
                    return;
                }
                hasSubMacros = true;

                foreach (name, param; instance2.params)
                    foreach (instanceParam; param.instances)
                        foreach (t; instanceParam.macroTrees)
                            visitTree(t, condition, flags, instanceParam, outsideFunction, outsideMixin);

                if (instance2.macroDeclaration !is null && instance2.macroDeclaration.type == DeclarationType.macroParam)
                    isMacroParam = true;

                if ((flags & Flags.addInterpolatMixins)
                        || instance2.macroTranslation != MacroTranslation.mixin_)
                    if (instance2.macroTranslation != MacroTranslation.none
                            && instance2.macroDeclaration !is null
                            && !instance2.macroDeclaration.name.among("Q_OBJECT"))
                        add(instance2.macroDeclaration, condition,
                                outsideFunction, outsideMixin, tree.start);
                if (instance2.macroTranslation == MacroTranslation.enumValue
                        || instance2.macroTranslation == MacroTranslation.alias_)
                {
                    isValueMacro = true;
                    return;
                }
                if (instance2.macroTranslation == MacroTranslation.mixin_)
                {
                    isMixinMacro = true;
                }
                foreach (t; instance2.macroTrees)
                    visitTree(t, condition, flags, instance2, outsideFunction, outsideMixin && !isMixinMacro);
            }

            onDep(data.macroReplacement[tree]);
            if (isValueMacro || isMacroParam || hasSubMacros)
                return;
        }
        if (semantic.extraInfo(tree).declarations.length
                && !(tree.nameOrContent == "ParameterDeclarationAbstract"
                    && (flags & Flags.inTemplate) != 0))
        {
            bool used;
            foreach (d; semantic.extraInfo(tree).declarations)
            {
                if (!isDeclarationBlacklisted(data, d))
                    used = true;
            }
            if (!used)
                return;
        }
        if (flags & Flags.addNormal)
        {
            foreach (x; semantic.extraInfo(tree).referenced.entries)
            {
                if (x.data.scope_.isRootNamespaceScope)
                {
                    foreach (e; x.data.entries)
                    {
                        if (e.data.flags & DeclarationFlags.templateSpecialization)
                            continue;
                        if (e.data.tree.isValid && e.data.tree.nonterminalID == nonterminalIDFor!"Enumerator")
                            visitType(semantic.extraInfo(tree).type, condition,
                                    outsideFunction, outsideMixin, tree.start);
                    }
                }
            }
            if (semantic.extraInfo(tree).referenced.entries.length)
            {
                ConditionMap!Declaration realDecl;
                findRealDecl(tree, realDecl, condition, data, true /*allowType*/ , d.scope_);
                foreach (e; realDecl.entries)
                {
                    if (e.data.flags & DeclarationFlags.templateSpecialization)
                        continue;
                    if (e.data.scope_.isRootNamespaceScope)
                    {
                        add(e.data, e.condition, outsideFunction, outsideMixin, tree.start);
                    }
                }
            }
            if (!tree.nameOrContent.among("PostfixExpression") && (!parent.isValid
                    || !parent.nonterminalID.nonterminalIDAmong!("PostfixExpression"))
                    && !isTreeExpression(tree, semantic) && !(parent.isValid
                        && parent.nameOrContent == "QualifiedId"
                        && tree.nameOrContent == "NameIdentifier"))
                visitType(semantic.extraInfo(tree).type, condition,
                        outsideFunction, outsideMixin, tree.start);
            if (currentMacroInstance is null)
            {
                immutable(Formula)* needsCastCondition = semantic.logicSystem.false_;
                immutable(Formula)* needsCastStaticArrayCondition = semantic.logicSystem.false_;
                calcNeedsCast(needsCastCondition, needsCastStaticArrayCondition,
                        data, tree, condition, null, null);

                if (!needsCastCondition.isFalse || !needsCastStaticArrayCondition.isFalse)
                    visitType(semantic.extraInfo2(tree).convertedType,
                            condition, outsideFunction, outsideMixin, tree.start);
            }
        }

        auto dummyDeclaration = getDummyDeclaration(tree, data, semantic);
        if (dummyDeclaration !is null)
            add2(dummyDeclaration, condition, outsideFunction, outsideMixin, tree.start);

        foreach (i, c; tree.childs)
        {
            immutable(Formula)* condition2 = condition;
            if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                ConditionTree ctree = tree.toConditionTree;
                condition2 = semantic.logicSystem.and(condition, ctree.conditions[i]);
            }
            visitTree(c, condition2, flags, null, outsideFunction, outsideMixin);
        }
        if (tree.nameOrContent.startsWith("MemberDeclaration"))
        {
            foreach (d; semantic.extraInfo(tree).declarations)
            {
                if (d.type != DeclarationType.varOrFunc)
                    continue;
                if (isDeclarationBlacklisted(data, d))
                    continue;
                foreach (e; d.realDeclaration.entries)
                {
                    foreach (d2, di; getDeclDependencies(e.data, data))
                        add2(d2, di.condition, di.outsideFunction, di.outsideMixin, tree.start);
                }
            }
        }
    }

    if (d.type == DeclarationType.type
            && (d.flags & DeclarationFlags.typedef_) != 0
            && isSelfTypedef(d, data))
    {
        cache[d] = r;
        return r;
    }
    visitTree(d.tree, d.condition, Flags.all, null, true, true);
    foreach (e; d.realDeclaration.entries)
    {
        add2(e.data, e.condition, true, true, d.location.start);
    }

    if (d.type == DeclarationType.macro_)
    {
        MacroDeclaration macroDeclaration = cast(MacroDeclaration) d;
        foreach (instance; macroDeclaration.instances)
        {
            if (instance.macroTranslation == MacroTranslation.enumValue
                    || instance.macroTranslation == MacroTranslation.alias_)
            {
                foreach (t; instance.macroTrees)
                    visitTree(t, d.condition, Flags.all, instance, true, true);
            }
        }
    }

    foreach (t; findParentTemplateDeclarations(d.tree, semantic))
    {
        visitTree(t.childs[2], d.condition, Flags.all | Flags.inTemplate, null, true, true);
    }

    cache[d] = r;

    return r;
}

void addDeclaration(TodoList!Declaration todo, Declaration d, DWriterData data)
{
    auto semantic = data.semantic;

    if (d.type == DeclarationType.forwardScope)
        return;

    Appender!(Declaration[]) declsApp;
    foreach (d2, _; getDeclDependencies(d, data))
    {
        if (d2.type == DeclarationType.dummy)
            continue;
        declsApp.put(d2);
    }
    auto decls = declsApp.data;

    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));
    foreach (d2; decls)
    {
        todo.addAfter!({ addDeclaration(todo, d2, data); })(d2);
    }
}

bool includeDeclsForFile(DWriterData data, string filename)
{
    return data.options.includeAllDecls
        || filename in data.inputFilesSet
        || data.options.includeDeclFilenamePatterns.match(filename);
}

long getDeclarationOrder(Declaration d, DWriterData data)
{
    foreach_reverse (ref pattern; data.options.declarationOrder)
    {
        DeclarationMatch match;
        if (isDeclarationMatch(pattern.match, match, d, data.semantic))
        {
            return pattern.order;
        }
    }
    return 0;
}

bool cmpDeclarationLoc2(Declaration a, Declaration b, DWriterData data)
{
    long orderA = getDeclarationOrder(a, data);
    long orderB = getDeclarationOrder(b, data);
    if (orderA != orderB)
        return orderA < orderB;
    return cmpDeclarationLoc(a, b, data.semantic);
}

void selectDeclarations(DWriterData data)
{
    auto semantic = data.semantic;

    string getDeclCategory(Declaration d, ref IteratePPVersions ppVersion)
    {
        string category;
        if (d.type == DeclarationType.varOrFunc)
        {
            if (d.declaratorTree.nonterminalID == nonterminalIDFor!"InitDeclarator"
                    && (d.flags & DeclarationFlags.function_) == 0)
                category = "Init ";
            category ~= "VarOrFunc";
            if ((d.flags & DeclarationFlags.function_) == 0
                    && (d.flags & DeclarationFlags.static_) != 0)
            {
                category ~= " file:" ~ d.location.context.rootFilename;
            }
            if ((d.flags & DeclarationFlags.function_) != 0)
            {
                category ~= " type: " ~ typeToString(filterType(d.type2,
                        ppVersion.condition, semantic, FilterTypeFlags.replaceRealTypes
                        | FilterTypeFlags.simplifyFunctionType | FilterTypeFlags.removeTypedef));
            }
        }
        else if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0)
        {
            QualType t = chooseType(d.type2, ppVersion, true);

            category = text("typedef ", cast(void*) t.type, " ", t.qualifiers,
                    " ", getDeclarationFilename(d, data).moduleName);
        }
        else if (d.type == DeclarationType.type)
            category = "type";
        Scope s = d.scope_;
        if (d.scope_ !is null && d.tree in d.scope_.childScopeByTree)
        {
            foreach (e; d.scope_.childScopeByTree[d.tree].extraParentScopes.entries)
            {
                if (e.data.type != ExtraScopeType.namespace)
                    continue;
                if (!isInCorrectVersion(ppVersion, e.condition))
                    continue;
                s = e.data.scope_;
                break;
            }
        }
        while (s !is null && s.tree.isValid) // not namespace
            s = s.parentScope;
        if (s !is null)
            category ~= " namespace " ~ s.toString();
        return category;
    }

    Appender!(Declaration[]) tmpDeclarationBuffer;
    bool[Declaration] added;
    void onScope0(Scope s)
    {
        foreach (name, entries; s.symbols)
        {
            foreach (e; entries.entries ~ entries.entriesRedundant)
            {
                if (isDeclarationBlacklisted(data, e.data))
                    continue;
                if (e.data.type == DeclarationType.namespace)
                    continue;
                if (e.data !in added)
                {
                    tmpDeclarationBuffer.put(e.data);
                    added[e.data] = true;
                }
                foreach (e2; e.data.realDeclaration.entries)
                {
                    if (isDeclarationBlacklisted(data, e2.data))
                        continue;
                    if (e2.data !in added)
                    {
                        tmpDeclarationBuffer.put(e2.data);
                        added[e2.data] = true;
                    }
                }
            }
        }
        foreach (name, s2; s.childNamespaces)
            onScope0(s2);
    }

    onScope0(semantic.rootScope);
    tmpDeclarationBuffer.data.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));

    immutable(Formula)*[string][string] hasNonForwardDecl;
    foreach (d; tmpDeclarationBuffer.data)
    {
        if (d.flags & DeclarationFlags.forward)
            continue;
        if (d.name.length == 0)
            continue;
        if ((d.flags & DeclarationFlags.typedef_) != 0)
            continue;
        /*if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0
            && d.name == typeToCode(d.type2, data, d.condition, null))
            continue; // self alias*/

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, d.condition);

            string category = getDeclCategory(d, ppVersion);

            immutable(Formula)* prev = semantic.logicSystem.false_;
            auto e = category in hasNonForwardDecl;
            if (!e)
            {
                hasNonForwardDecl[category] = null;
                e = category in hasNonForwardDecl;
            }
            if (d.name in *e)
                prev = (*e)[d.name];
            (*e)[d.name] = semantic.logicSystem.or(prev, ppVersion.condition);
        }
    }

    immutable(Formula)*[string][string] doneForwardDecl;

    immutable(Formula)*[Declaration] forwardDecls;
    foreach (d; tmpDeclarationBuffer.data)
    {
        if (d.type == DeclarationType.forwardScope)
            continue;
        if (d.isRedundant)
        {
            forwardDecls[d] = d.condition;
            continue;
        }
        immutable(Formula)* skipForward = semantic.logicSystem.false_;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, d.condition);

            string category = getDeclCategory(d, ppVersion);
            if ((d.flags & DeclarationFlags.forward) != 0
                    || (d.flags & DeclarationFlags.typedef_) != 0)
            {
                auto e = category in hasNonForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
                e = category in doneForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
            }
            if (d.type == DeclarationType.varOrFunc && d.declaratorTree.name != "InitDeclarator"
                    && (d.flags & DeclarationFlags.function_) == 0)
            {
                string category2 = "Init " ~ category;
                auto e = category2 in hasNonForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
            }
            if (d.flags & DeclarationFlags.enumerator)
                continue;
            if (d.name.among("size_t", "ptrdiff_t"))
                continue;

            if ((d.flags & DeclarationFlags.forward) != 0
                    || (d.flags & DeclarationFlags.typedef_) != 0)
            {
                if (category !in doneForwardDecl)
                    doneForwardDecl[category] = null;
                if (d.name !in doneForwardDecl[category])
                    doneForwardDecl[category][d.name] = ppVersion.condition;
                else
                    doneForwardDecl[category][d.name] = semantic.logicSystem.or(
                            doneForwardDecl[category][d.name], ppVersion.condition);
            }
        }
        forwardDecls[d] = skipForward;
    }
    data.forwardDecls = forwardDecls;

    tmpDeclarationBuffer.clear();
    void onScope(Scope s)
    {
        foreach (name, entries; s.symbols)
        {
            foreach (e; entries.entries ~ entries.entriesRedundant)
            {
                if (isDeclarationBlacklisted(data, e.data))
                    continue;
                if (e.data.type == DeclarationType.namespace)
                    continue;
                immutable(LocationContext)* locContext = e.data.location.context;
                if (locContext is null)
                    continue;
                while (locContext !is null && locContext.name.length)
                    locContext = locContext.prev;
                if (locContext.contextDepth != 1)
                    continue;
                if (!includeDeclsForFile(data, locContext.filename))
                    continue;
                tmpDeclarationBuffer.put(e.data);
            }
        }
        foreach (name, s2; s.childNamespaces)
            onScope(s2);
    }

    onScope(semantic.rootScope);

    foreach (key, d; data.sourceTokenManager.macroDeclarations)
    {
        if (includeDeclsForFile(data, d.location.context.filename))
        {
            tmpDeclarationBuffer.put(d);
        }
    }
    tmpDeclarationBuffer.put(data.sourceTokenManager.commentDeclarations.data);

    auto decls = tmpDeclarationBuffer.data;

    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));
    auto todo = new TodoList!Declaration;
    foreach (d; decls)
    {
        todo.addAfter!({ addDeclaration(todo, d, data); })(d);
    }
    decls = todo.data;
    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));

    foreach (d; decls)
    {
        if (d.type == DeclarationType.forwardScope)
            continue;
        DFilename filenameNoExt = getDeclarationFilename(d, data);
        if (d.name.among("size_t", "ptrdiff_t"))
            continue;
        if (d.name.among("__assert_fail", "assert"))
            continue;

        data.declsByFile[filenameNoExt] ~= d;
    }

    data.decls = decls;

    foreach (d; decls)
    {
        if (d.type.among(DeclarationType.forwardScope, DeclarationType.dummy, DeclarationType.namespace, DeclarationType.namespaceBegin, DeclarationType.namespaceEnd))
            continue;
        if (d !in forwardDecls)
            forwardDecls[d] = semantic.logicSystem.false_;
    }

    foreach (name, ref decls2; data.declsByFile)
    {
        decls2.sort!((a, b) => cmpDeclarationLoc2(a, b, data));

        ImportInfo[string] neededImports;
        bool[string] neededPackages;
        foreach (d; decls2)
        {
            Appender!(Tuple!(Declaration, immutable(Formula)*, bool, LocationX)[]) depsApp;
            foreach (d2, di2; getDeclDependencies(d, data))
            {
                if (!di2.outsideMixin)
                    continue;
                if (d2.name.among("size_t", "ptrdiff_t"))
                    continue;
                if (d2.name.among("__assert_fail", "assert"))
                    continue;
                depsApp.put(tuple!(Declaration, immutable(Formula)*, bool,
                        LocationX)(d2, di2.condition, di2.outsideFunction, di2.locAdded));
            }
            depsApp.data.sort!((a, b) => cmpDeclarationLoc(a[0], b[0], semantic));
            foreach (t2; depsApp.data)
            {
                auto d2 = t2[0];
                string filenameNoExt = getDeclarationFilename(d2, data).moduleName;
                if (d2.type != DeclarationType.dummy && d2 !in forwardDecls)
                    continue;
                immutable(Formula)* condition = semantic.logicSystem.and(
                        semantic.logicSystem.and(semantic.logicSystem.and(d.condition,
                        d2.condition), forwardDecls[d].negated), t2[1]);
                if (d2 in forwardDecls)
                    condition = semantic.logicSystem.and(condition, forwardDecls[d2].negated);
                if (filenameNoExt != name.moduleName && !condition.isFalse)
                {
                    ImportInfo importInfo;
                    if (filenameNoExt in neededImports)
                    {
                        importInfo = neededImports[filenameNoExt];
                        importInfo.condition = semantic.logicSystem.or(importInfo.condition,
                                condition);
                        importInfo.outsideFunction |= t2[2];
                    }
                    else
                    {
                        importInfo = new ImportInfo;
                        neededImports[filenameNoExt] = importInfo;
                        importInfo.condition = condition;
                        importInfo.outsideFunction = t2[2];
                    }
                    if (importInfo.examples.length < 5)
                    {
                        importInfo.examples ~= ImportExample(d, d2, t2[3]);
                    }
                    neededPackages[filenameNoExt.packageName] = true;
                }
            }
        }
        data.importGraph[name] = neededImports;
        data.importedPackagesGraph[name] = neededPackages;
    }
}
