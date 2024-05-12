
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.macrodeclaration;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.dtypecode;
import cppconv.dwriter;
import cppconv.filecache;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.typecons;

enum MacroTranslation
{
    none,
    mixin_,
    enumValue,
    alias_,
    builtin, // e.g. assert
}

struct MacroParamName
{
    string usedName;
    string realName;
    size_t index;
}

class MacroDeclaration : Declaration
{
    MacroDeclarationInstance[] instances;
    string[string] nameByCode;
    Tree definition;
    MacroDeclarationInstance funcMacroInstance;
}

class MacroDeclarationInstance
{
    MacroDeclaration macroDeclaration;
    LocationContextInfo locationContextInfo;
    Tree[] macroTrees;
    Tree firstUsedTree;
    string instanceCode;
    size_t realCodeStart;
    size_t realCodeEnd;
    string usedName;
    MacroTranslation macroTranslation;
    MacroDeclarationInstance[] extraDeps;
    MacroDeclaration[string] params;
    MacroParamName[] paramNames;
    bool hasMacroConcat;
    bool hasParamExpansion;
}

void checkDisconnectedDeclSeq(Tree tree, immutable(Formula)* condition, Semantic semantic,
    immutable(LocationContext)* locationContext,
    ref immutable(Formula)* conditionInMacro, ref immutable(Formula)* conditionOutsideMacro)
{
    auto logicSystem = semantic.logicSystem;
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
            checkDisconnectedDeclSeq(c, condition, semantic, locationContext, conditionInMacro, conditionOutsideMacro);
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        foreach (i, c; tree.childs)
        {
            auto condition2 = logicSystem.and(condition, logicSystem.or(mdata.conditions[i], mdata.mergedCondition));
            if (!condition2.isFalse)
                checkDisconnectedDeclSeq(c, condition2, semantic, locationContext, conditionInMacro, conditionOutsideMacro);
        }
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        foreach (i, c; tree.childs)
            checkDisconnectedDeclSeq(c, logicSystem.and(condition, ctree.conditions[i]), semantic, locationContext, conditionInMacro, conditionOutsideMacro);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq")
    {
        foreach (c; tree.childs)
            checkDisconnectedDeclSeq(c, condition, semantic, locationContext, conditionInMacro, conditionOutsideMacro);
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("TypeKeyword"))
    {
        if (isParentOf(locationContext, tree.location.context))
            conditionInMacro = logicSystem.or(conditionInMacro, condition);
        else
            conditionOutsideMacro = logicSystem.or(conditionOutsideMacro, condition);
    }
}

void collectMacroInstances(DWriterData data, Semantic mergedSemantic,
        LocationContextInfo locationContextInfo)
{
    auto locationContext = locationContextInfo.locationContext;
    if (locationContext !is null && locationContext.name.length
            && locationContext.name == "^" && locationContext.filename.length)
    {
        string macroName = locationContext.prev.name;
        string paramName;
        foreach (i, char c; macroName)
        {
            if (c == '.')
            {
                paramName = macroName[i + 1 .. $];
                macroName = macroName[0 .. i];
                break;
            }
        }

        data.macroInstanceByLocation[locationContextInfo.locationContext]
            = ConditionMap!MacroDeclarationInstance.init;

        size_t numCombinations;
        foreach (combination; iterateCombinations())
        {
            numCombinations++;
            if (numCombinations > 100)
            {
                writeln("many combinations ", numCombinations, " ", locationStr(locationContext));
                break;
            }
            immutable(Formula)* firstCondition = locationContextInfo.condition;
            if (firstCondition is null)
                firstCondition = mergedSemantic.logicSystem.true_;
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    mergedSemantic.logicSystem, firstCondition, null,
                    mergedSemantic.mergedTreeDatas);

            foreach (e; locationContextInfo.trees.entries)
            {
                isInCorrectVersion(ppVersion, e.condition);
            }

            MacroDeclarationInstance instance;

            if (paramName.length)
            {
                if (locationContextInfo.mappedInParam
                        && locationContextInfo.trees.entries.length == 0)
                    continue;

                immutable(LocationContext)* locationContextMacro = macroFromParam(
                        locationContext.prev);
                auto instance2Map = locationContextMacro in data.macroInstanceByLocation;
                if (instance2Map)
                {
                    auto instance2 = instance2Map.choose(ppVersion);
                    instance = new MacroDeclarationInstance;
                    if (instance2 !is null)
                    {
                        if (paramName !in instance2.params)
                        {
                            MacroDeclaration macroDeclaration2 = new MacroDeclaration;
                            macroDeclaration2.type = DeclarationType.macroParam;
                            macroDeclaration2.name = paramName;
                            macroDeclaration2.funcMacroInstance = instance2;
                            instance2.params[paramName] = macroDeclaration2;
                        }
                        instance2.params[paramName].instances ~= instance;
                        instance.macroDeclaration = instance2.params[paramName];

                        immutable(LocationContext)* loc3 = locationContext;
                        while (loc3 !is locationContextMacro)
                        {
                            if (loc3.name == "#")
                                instance.hasParamExpansion = true;
                            if (loc3.name == "##")
                                instance.hasMacroConcat = true;
                            loc3 = loc3.prev;
                        }
                    }
                }
            }
            if (instance is null)
                instance = new MacroDeclarationInstance;

            data.macroInstanceByLocation[locationContextInfo.locationContext].addNew(
                    ppVersion.condition, instance, mergedSemantic.logicSystem);
        }

        bool anyChildComplex; // e.g. ParamConcat
        for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                child = child.next)
        {
            /*if (child.locationContext.name == "##")
                anyChildComplex = true;*/
            collectMacroInstances(data, mergedSemantic, child);
        }

        if (anyChildComplex)
            return;

        if (macroName in data.options.macroReplacements)
            return;

        if (macroName.among("va_start", "va_end", "va_copy", "va_arg", "va_list", "bool"))
            return;
        if (macroName.among("QMETATYPE_D_IMPL", "QT_FOR_EACH_STATIC_PRIMITIVE_TYPE",
                "QT_FOR_EACH_STATIC_PRIMITIVE_POINTER", "QT_FOR_EACH_STATIC_CORE_POINTER"))
            return;

        if (locationContextInfo.warnings.length)
            return;

        outer: foreach (instanceEntry; data
                .macroInstanceByLocation[locationContextInfo.locationContext].entries)
        {
            MacroDeclarationInstance instance = instanceEntry.data;
            instance.locationContextInfo = locationContextInfo;

            Tree[] macroTrees;
            foreach (ref e; locationContextInfo.trees.entries)
            {
                if (mergedSemantic.logicSystem.and(e.condition, instanceEntry.condition).isFalse)
                    continue;
                if (macroTrees.length)
                    continue outer;
                if (e.data.length < 1)
                    continue outer;
                macroTrees = e.data;
            }
            if (macroTrees.length == 0)
                continue;
            if (macroTrees.length == 1 && macroTrees[0].nodeType == NodeType.array)
            {
                if (macroTrees[0].childs.length < 1)
                    continue;
                macroTrees = macroTrees[0].childs;
            }

            instance.macroTrees = macroTrees;

            foreach (t; instance.macroTrees)
                if (t in data.macroReplacement && data.macroReplacement[t] !is null)
                    instance.extraDeps.addOnce(data.macroReplacement[t]);

            foreach (t; instance.macroTrees)
            {
                data.macroReplacement[t] = instance;
            }

            if (paramName.length)
            {
                continue;
            }

            if (!isParentOf(locationContext, macroTrees[0].start.context)) // ParamConcat
                continue;

            if (macroTrees.length == 1 && macroTrees[0].nameOrContent == "NameIdentifier"
                    && macroTrees[0].childs[0].nameOrContent == macroName)
                continue;

            immutable(LocationContext)* locationContext2 = data.locationContextMap.getLocationContext(
                    immutable(LocationContext)(null, LocationN.init,
                    LocationN.LocationDiff.init, "", locationContext.prev.filename));
            LocationRangeX l = LocationRangeX(LocationX(locationContext.startInPrev,
                    locationContext2), locationContext.lengthInPrev);

            Tuple!(string, LocationRangeX) key = tuple!(string, LocationRangeX)(macroName, l);
            MacroDeclaration macroDeclaration;
            if (key !in data.sourceTokenManager.macroDeclarations)
                continue;

            macroDeclaration = data.sourceTokenManager.macroDeclarations[key];

            instance.macroDeclaration = macroDeclaration;

            macroDeclaration.instances ~= instance;

            Tree parent = getRealParent(macroTrees[0], mergedSemantic);

            bool allParamsLeastOneInstance = true;
            bool allParamsOneInstance = true;
            bool allParamsPossibleMixin = true;
            bool allParamsLiteral = true;
            bool allParamsNoConcat = true;
            bool allParamsNoExpansion = true;
            bool allParamsStringLiterals = true;
            if (macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
            {
                foreach (p; macroDeclaration.definition.childs[7].childs)
                {
                    if (p.nodeType == NodeType.token || p.childs.length == 1)
                        continue;
                    string paramName2 = p.childs[1].content;
                    if (paramName2 == "...")
                        paramName2 = "__VA_ARGS__";
                    if (paramName2 !in instance.params
                            || instance.params[paramName2].instances.length != 1)
                    {
                        allParamsOneInstance = false;
                    }
                    if (paramName2 !in instance.params
                            || instance.params[paramName2].instances.length < 1)
                    {
                        allParamsLeastOneInstance = false;
                        continue;
                    }
                    foreach (x; instance.params[paramName2].instances)
                    {
                        if (!isTreePossibleMixin(x.macroTrees, mergedSemantic))
                        {
                            allParamsPossibleMixin = false;
                        }
                        bool isType;
                        if (x.macroTrees.length != 1
                                || !isConstExpression(x.macroTrees[0], mergedSemantic, isType))
                        {
                            allParamsLiteral = false;
                        }
                        if (x.hasParamExpansion)
                            allParamsNoExpansion = false;
                        if (x.hasMacroConcat)
                            allParamsNoConcat = false;

                        bool allStringLiteral = true;
                        foreach (t; x.macroTrees)
                            if (t.nonterminalID != nonterminalIDFor!"StringLiteral2")
                                allStringLiteral = false;
                        if (x.macroTrees.length == 0 || !allStringLiteral)
                            allParamsStringLiterals = false;
                    }
                }
            }
            bool allTreesStringLiteral = true;
            foreach (t; macroTrees)
                if (t.nonterminalID != nonterminalIDFor!"StringLiteral2")
                    allTreesStringLiteral = false;

            bool hasDisconnectedDeclSeq;
            if (macroTrees.length == 1)
            {
                if (parent.isValid && parent.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq")
                {
                    immutable(Formula)* conditionInMacro = mergedSemantic.logicSystem.false_;
                    immutable(Formula)* conditionOutsideMacro = mergedSemantic.logicSystem.false_;
                    checkDisconnectedDeclSeq(parent, mergedSemantic.logicSystem.true_, mergedSemantic, locationContextInfo.locationContext, conditionInMacro, conditionOutsideMacro);
                    if (!mergedSemantic.logicSystem.and(conditionInMacro, conditionOutsideMacro).isFalse)
                        hasDisconnectedDeclSeq = true;
                }
            }
            bool isType;
            if (macroName == "assert" && macroTrees.length == 1
                    && macroTrees[0].nonterminalID == nonterminalIDFor!"CppConvAssertExpression")
            {
                foreach (ps; instance.params)
                    foreach (p; ps.instances)
                    {
                        p.macroTranslation = MacroTranslation.builtin;
                    }
                instance.macroTranslation = MacroTranslation.builtin;
            }
            else if (macroTrees.length > 0 && allTreesStringLiteral && allParamsStringLiterals)
            {
                foreach (ps; instance.params)
                    foreach (p; ps.instances)
                    {
                        p.macroTranslation = MacroTranslation.enumValue;
                    }
                instance.macroTranslation = MacroTranslation.enumValue;
            }
            else if (allParamsNoConcat && allParamsNoExpansion && allParamsOneInstance && allParamsLiteral
                    && /*macroDeclaration.definition.nonterminalID == nonterminalIDFor!"VarDefine" &&*/ macroTrees.length == 1
                    && isConstExpression(macroTrees[0], mergedSemantic, isType) && !hasDisconnectedDeclSeq)
            {
                foreach (ps; instance.params)
                    foreach (p; ps.instances)
                    {
                        bool isType2;
                        isConstExpression(p.macroTrees[0], mergedSemantic, isType2);
                        if (isType2)
                            p.macroTranslation = MacroTranslation.alias_;
                        else
                            p.macroTranslation = MacroTranslation.enumValue;
                    }
                if (isType)
                    instance.macroTranslation = MacroTranslation.alias_;
                else
                    instance.macroTranslation = MacroTranslation.enumValue;
            }
            else if (allParamsNoConcat && allParamsNoExpansion
                    && macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"VarDefine"
                    && macroTrees.length == 1
                    && isTreeGlobalReference(macroTrees[0], mergedSemantic))
            {
                instance.macroTranslation = MacroTranslation.alias_;
            }
            else if ( /*allParamsOneInstance && */ allParamsNoConcat && allParamsPossibleMixin
                    && isTreePossibleMixin(macroTrees, mergedSemantic))
            {
                foreach (ps; instance.params)
                    foreach (p; ps.instances)
                        p.macroTranslation = MacroTranslation.mixin_;
                instance.macroTranslation = MacroTranslation.mixin_;
            }
        }
    }
    else
    {
        for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                child = child.next)
        {
            collectMacroInstances(data, mergedSemantic, child);
        }
    }
}

void applyMacroInstances(DWriterData data, Semantic mergedSemantic,
        LocationContextInfo locationContextInfo)
{
    for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
            child = child.next)
    {
        applyMacroInstances(data, mergedSemantic, child);
    }

    auto locationContext = locationContextInfo.locationContext;

    if (locationContextInfo.locationContext !in data.macroInstanceByLocation)
        return;

    static Appender!(SourceToken[]) sourceTokens;

    foreach (instanceEntry; data
            .macroInstanceByLocation[locationContextInfo.locationContext].entries)
    {
        MacroDeclarationInstance instance = instanceEntry.data;

        if (instance.macroTranslation == MacroTranslation.none)
            continue;

        data.currentFilename = getDeclarationFilename(instance.macroTrees[0].location,
                data, "" /*instance.macroDeclaration.name*/ , DeclarationFlags.none);
        data.importGraphHere = data.importGraph.get(data.currentFilename, null);
        data.importedPackagesGraphHere = data.importedPackagesGraph.get(data.currentFilename, null);
        data.versionReplacementsOr = null;
        data.afterStringLiteral = false;

        auto instanceCondition = locationContextInfo.condition;
        if (instanceCondition is null)
            instanceCondition = mergedSemantic.logicSystem.true_;
        immutable(Formula)* usedConditionForFile = .usedConditionForFile(data,
                RealFilename(locationContextInfo.locationContext.rootFilename), true);
        if (usedConditionForFile !is null)
            instanceCondition = mergedSemantic.logicSystem.and(instanceCondition,
                    usedConditionForFile);
        CodeWriter code;
        code.indentStr = data.options.indent;
        code.incIndent;

        assert(data.sourceTokenManager.tokensLeft.data.length == 0);
        LocationRangeX locRange;
        MacroDeclarationInstance instance2;
        MacroDeclaration macroDeclaration2;
        if (instance.macroDeclaration.type == DeclarationType.macroParam)
        {
            if (instance.macroDeclaration.type == DeclarationType.macroParam
                    && instance.hasParamExpansion)
            {
                LocationContextInfo info = instance.locationContextInfo;
                while (info.locationContext.name != "#")
                    info = info.parent;

                locRange = info.sourceTokens.childs[1].location;
            }
            else if (locationContext.parentLocation.context.filename.length)
            {
                locRange.setStartLength(LocationX(locationContext.parentLocation.start.loc,
                        locationContext), locationContext.parentLocation.inputLength);
                assert(locationContext.filename == locationContext.parentLocation.context.filename);
            }

            if (locRange.context !is null)
            {
                immutable(LocationContext)* locationContextMacro = macroFromParam(
                        locationContext.prev);
                locationContextMacro = locationContextMacro.prev.prev.prev;

                if (locationContextMacro.name.length)
                {
                    immutable(LocationContext)* locationContext2 = data.locationContextMap.getLocationContext(
                            immutable(LocationContext)(null, LocationN.init,
                            LocationN.LocationDiff.init, "", locationContextMacro.prev.filename));
                    LocationRangeX l = LocationRangeX(LocationX(locationContextMacro.startInPrev,
                            locationContext2), locationContextMacro.lengthInPrev);

                    string macroName = locationContextMacro.prev.name;

                    Tuple!(string, LocationRangeX) key = tuple!(string, LocationRangeX)(macroName, l);

                    if (locationContextMacro in data.macroInstanceByLocation)
                        instance2 = data.macroInstanceByLocation[locationContextMacro]
                            .entries[0].data;

                    if (key in data.sourceTokenManager.macroDeclarations
                            && instance2 !is null && instance2.macroDeclaration !is null
                            && instance2.macroDeclaration.type == DeclarationType.macro_)
                    {
                        macroDeclaration2 = data.sourceTokenManager.macroDeclarations[key];
                        assert(instance2.macroDeclaration is macroDeclaration2);
                        if (instance2.macroTranslation == MacroTranslation.none)
                            macroDeclaration2 = null;
                    }
                }
            }
            else
            {
                code.write(" /* TODO: strange macro */ ");
            }
        }
        else
        {
            macroDeclaration2 = instance.macroDeclaration;
            locRange.setStartLength(LocationX(instance.macroDeclaration.definition.location.start.loc,
                    locationContext), instance.macroDeclaration.definition.location.inputLength);
            assert(
                    instance.macroDeclaration.definition.location.context.filename
                    == locationContext.filename);
        }
        if (!locationContext.isParentOf(instance.macroTrees[0].start.context))
            locRange = LocationRangeX.init;
        if (locRange.context !is null)
        {
            foreach (i; 0 .. locRange.context.contextDepth - 1)
                data.sourceTokenManager.tokensLeft.put(SourceToken[].init);
            SourceToken[] tokens;

            if (macroDeclaration2 is null)
            {
                tokens = data.sourceTokenManager.sourceTokens[RealFilename(
                            locRange.context.filename)];
            }
            else
            {
                sourceTokens.clear();
                foreach (c; macroDeclaration2.definition.childs[$ - 2].childs)
                    if (c.content.length)
                        sourceTokens.put(SourceToken(c, macroDeclaration2.condition, true));
                foreach (t; macroDeclaration2.definition.childs[$ - 1].childs)
                {
                    if (t.childs[0].content.length)
                        sourceTokens.put(SourceToken(t.childs[0],
                                macroDeclaration2.condition, false));
                    foreach (c; t.childs[1].childs)
                        if (c.content.length)
                            sourceTokens.put(SourceToken(c, macroDeclaration2.condition, true));
                }
                tokens = sourceTokens.data;
            }
            tokens = tokens[interpolationSearch!(".token.start.loc",
                        "<")(tokens, locRange.start.loc) .. $];
            tokens = tokens[0 .. interpolationSearch!(".token.end.loc",
                        "<=")(tokens, locRange.end.loc)];

            data.sourceTokenManager.tokensLeft.put(tokens);
            data.sourceTokenManager.locDone = locRange.start;
            data.sourceTokenManager.tokensContext = locRange.context;
        }

        data.sourceTokenManager.inInterpolateMixin = instance.macroDeclaration.type == DeclarationType.macro_
            && instance.macroTranslation == MacroTranslation.mixin_
            && instance.macroDeclaration.definition.nonterminalID
            == preprocNonterminalIDFor!"FuncDefine";
        data.currentMacroInstance = instance.macroDeclaration.type == DeclarationType.macroParam ? instance2 : instance;

        Tree[] usedTrees = instance.macroTrees;
        while (usedTrees.length == 1
                && usedTrees[0].nonterminalID == nonterminalIDFor!"InitializerClause")
            usedTrees = usedTrees[0].childs[0 .. 1];
        instance.firstUsedTree = usedTrees[0];

        TreeToCodeFlags treeToCodeFlags = TreeToCodeFlags.none;
        if (instance.macroDeclaration.type == DeclarationType.macro_)
            treeToCodeFlags |= TreeToCodeFlags.skipCasts;
        if (instance.macroDeclaration.type == DeclarationType.macroParam && instance.macroTrees.length == 1
                && instance.macroDeclaration.funcMacroInstance.macroTrees.length == 1
                && instance.macroTrees[0] is instance.macroDeclaration
                    .funcMacroInstance.macroTrees[0])
            treeToCodeFlags |= TreeToCodeFlags.skipCasts;
        size_t realCodeStart;
        size_t indexInParent;
        Tree parent = getRealParent(usedTrees[0], mergedSemantic, &indexInParent);
        if (instance.macroDeclaration.type == DeclarationType.macroParam
                && instance.hasParamExpansion)
        {
            LocationContextInfo info = instance.locationContextInfo;
            while (info.locationContext.name != "#")
                info = info.parent;

            foreach (t; info.sourceTokens.childs[1].childs)
                parseTreeToDCode(code, data, t, instanceCondition, null, treeToCodeFlags);
        }
        else if (parent.isValid && (parent.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq"
            || (parent.nonterminalID == nonterminalIDFor!"TypeId" && indexInParent == 0)))
        {
            ConditionMap!string codeType;
            CodeWriter codeAfterDeclSeq;
            codeAfterDeclSeq.indentStr = data.options.indent;
            bool afterTypeInDeclSeq;
            foreach (usedTree; usedTrees)
            {
                if (code.data.length == 0 && usedTree.isValid)
                {
                    writeComments(code, data, locationBeforeUsedMacro(usedTree, data, false));
                    realCodeStart = code.data.length;
                }
                if (usedTree.isValid)
                {
                    collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                            afterTypeInDeclSeq, usedTree, instanceCondition, data, null);
                }
            }

            ConditionMap!string realId;
            translateBuiltinAll(codeType, realId, instanceCondition, false, data);
            realId.removeFalseEntries();
            code.write(idMapToCode(realId, instanceCondition, data));
            code.write(codeAfterDeclSeq.data);
        }
        else
        {
            foreach (usedTree; usedTrees)
            {
                if (code.data.length == 0 && usedTree.isValid)
                {
                    writeComments(code, data, locationBeforeUsedMacro(usedTree, data, false));
                    realCodeStart = code.data.length;
                }
                parseTreeToDCode(code, data, usedTree, instanceCondition, null, treeToCodeFlags);
            }
        }

        data.sourceTokenManager.inInterpolateMixin = false;
        data.currentMacroInstance = null;

        size_t realCodeEnd = code.data.length;
        if (data.sourceTokenManager.tokensLeft.data.length)
            writeComments(code, data, locRange.end);

        data.sourceTokenManager.tokensContext = null;
        data.sourceTokenManager.tokensLeft.shrinkTo(0);

        instance.instanceCode = code.data.idup;
        if (instance.instanceCode.startsWith(data.options.indent))
        {
            instance.instanceCode = instance.instanceCode[data.options.indent.length .. $];
            if (realCodeStart)
            {
                assert(realCodeStart >= data.options.indent.length);
                realCodeStart -= data.options.indent.length;
            }
            assert(realCodeEnd >= data.options.indent.length);
            realCodeEnd -= data.options.indent.length;
        }
        instance.realCodeStart = realCodeStart;
        instance.realCodeEnd = realCodeEnd;

        if (instance.macroDeclaration.type == DeclarationType.macro_)
        {
            if (instance.macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
            {
                size_t index;
                foreach (i, p; instance.macroDeclaration.definition.childs[7].childs)
                {
                    if (p.nodeType == NodeType.token || p.childs.length == 1)
                        continue;
                    string paramName = p.childs[1].content;
                    if (paramName == "...")
                        paramName = "__VA_ARGS__";

                    MacroDeclarationInstance[] paramInstances;
                    if (paramName in instance.params)
                        paramInstances = instance.params[paramName].instances;
                    bool[string] paramAdded;
                    foreach (p2; paramInstances)
                    {
                        if (p2.usedName !in paramAdded)
                        {
                            instance.paramNames ~= MacroParamName(p2.usedName,
                                    p2.macroDeclaration.name, index);
                            paramAdded[p2.usedName] = true;
                        }
                    }
                    if (paramInstances.length == 0)
                    {
                        instance.paramNames ~= MacroParamName(paramName, paramName, index);
                    }
                    index++;
                }
            }
        }

        if (instance.macroDeclaration.type == DeclarationType.macro_)
        {
            auto key = text(instance.macroTranslation, " ",
                    instance.paramNames, " ", instance.instanceCode);
            if (key in instance.macroDeclaration.nameByCode)
            {
                instance.usedName = instance.macroDeclaration.nameByCode[key];
            }
            else
            {
                string name2 = getFreeName(instance.macroDeclaration.name,
                        getDeclarationFilename(instance.macroDeclaration.location,
                            data, "" /*instance.macroDeclaration.name*/ , DeclarationFlags.none),
                        instance.macroDeclaration.condition, data);
                instance.macroDeclaration.nameByCode[key] = name2;
                instance.usedName = name2;
            }
        }
        else if (instance.macroDeclaration.type == DeclarationType.macroParam)
        {
            auto key = text(instance.macroTranslation, " ", instance.instanceCode);
            if (key in instance.macroDeclaration.nameByCode)
            {
                instance.usedName = instance.macroDeclaration.nameByCode[key];
            }
            else
            {
                string name2;
                if (instance.macroDeclaration.nameByCode.length)
                    name2 = text(instance.macroDeclaration.name, "__",
                            instance.macroDeclaration.nameByCode.length + 2);
                else
                    name2 = replaceKeywords(instance.macroDeclaration.name);
                instance.macroDeclaration.nameByCode[key] = name2;
                instance.usedName = name2;
            }
        }

        foreach (ps; instance.params)
            foreach (p; ps.instances)
                foreach (t; p.macroTrees)
                    data.macroReplacement.remove(t);

        foreach (usedTree; usedTrees)
            data.macroReplacement[usedTree] = instance;

        sourceTokens.clear();
    }
}
