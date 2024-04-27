
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.mergedfile;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppparallelparser;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.filecache;
import cppconv.locationstack;
import cppconv.logic;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.nodetype;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.stdio;

alias Tree = CppParseTree;
private alias Context = cppconv.cppparallelparser.Context!(ParserWrapper);

struct MergedFileInstance
{
    immutable(Formula)* instanceCondition;
    immutable(Formula)* instanceConditionUsed;
    Tree[] mappedTrees;
    RealFilename tuFile;
    immutable(LocationContext)* locationPrefix;
    bool hasTree;
    string[] warnings;
    bool badInclude;
}

struct MacroInstanceInfo
{
    immutable(LocationContext)* locationContext;
    immutable(Formula)* condition;
    Tree sourceTokens;
    bool mappedInParam;
}

struct MergedFile
{
    RealFilename filename;
    Tree[] mergedTrees;
    MergedFileInstance[] instances;
    size_t[immutable(LocationContext*)] locPrefixToInstance;
    MergedFileInstance[][string] tuToInstances;
    SimpleClassAllocator!(CppParseTreeStruct*) treeAllocator;
    bool badInclude;
    size_t numTranslationUnits;
    LocConditions locConditions;
    LocationContextInfoMap locationContextInfoMap;
    MacroInstanceInfo[] macroInstances;
}

class LocationContextInfo
{
    immutable(LocationContext)* locationContext;
    ConditionMap!(Tree[]) trees;
    string[] warnings;
    bool badInclude;
    immutable(Formula)* condition;
    Tree sourceTokens;
    bool mappedInParam;
    LocationContextInfo next;
    LocationContextInfo firstChild;
    LocationContextInfo lastChild;
    LocationContextInfo parent;
}

SimpleClassAllocator!LocationContextInfo globalLocationContextInfoAllocator;
struct LocationContextInfoMap
{
    LocationContextInfo[immutable(LocationContext)*] locationContextInfos;
    SimpleClassAllocator!LocationContextInfo allocator;

    LocationContextInfo getLocationContextInfo(immutable(LocationContext)* locContext)
    {
        if (locContext !in locationContextInfos)
        {
            LocationContextInfo info;
            if (allocator !is null)
                info = allocator.allocate();
            else
                info = new LocationContextInfo;
            info.locationContext = locContext;
            locationContextInfos[locContext] = info;
            if (locContext !is null)
            {
                auto parentInfo = getLocationContextInfo(locContext.prev);
                info.parent = parentInfo;
                if (parentInfo.lastChild !is null)
                {
                    parentInfo.lastChild.next = info;
                    parentInfo.lastChild = info;
                }
                else
                {
                    parentInfo.firstChild = info;
                    parentInfo.lastChild = info;
                }
            }
            return info;
        }
        return locationContextInfos[locContext];
    }

    static void sortTree(LocationContextInfo locationContextInfo)
    {
        for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                child = child.next)
        {
            sortTree(child);
        }

        static Appender!(LocationContextInfo[]) app;
        scope (exit)
            app.clear();

        if (locationContextInfo.firstChild is null)
            return;

        for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                child = child.next)
        {
            app.put(child);
        }

        app.data.sort!((a, b) => a.locationContext.startInPrev < b.locationContext.startInPrev);

        locationContextInfo.firstChild = app.data[0];
        foreach (i; 0 .. app.data.length - 1)
        {
            app.data[i].next = app.data[i + 1];
        }
        app.data[$ - 1].next = null;
    }

    void sortTree()
    {
        sortTree(getLocationContextInfo(null));
    }

    void clear()
    {
        locationContextInfos.clear();
        locationContextInfos = null;
        if (allocator !is null)
            allocator.clearAll();
        allocator = null;
    }
}

void mergeFiles(Context rootContext, RealFilename inputFile, Context childContext,
        ref MergedFile[] mergedFiles)
{
    import std.datetime.stopwatch;

    auto sw = StopWatch(AutoStart.no);
    sw.start();

    assert(mergedFiles.length == 0);

    string[] sortedFiles;
    foreach (k, _; childContext.fileInstanceInfos)
        sortedFiles ~= k.name;
    sort(sortedFiles);
    mergedFiles = new MergedFile[sortedFiles.length];
    foreach (k; 0 .. sortedFiles.length)
    {
        mergedFiles[k].filename = RealFilename(sortedFiles[k]);
    }

    foreach (ref sortedFile; mergedFiles)
    {
        auto filename = sortedFile.filename;
        auto fileInstanceInfo = childContext.getFileInstanceInfo(filename);

        foreach (i, l; fileInstanceInfo.instanceLocations)
        {
            if (filename.name.endsWith("mathcalls-narrow.h") || filename.name.endsWith("mathcalls.h")
                    || filename.name.endsWith("mathcalls-helper-functions.h"))
                fileInstanceInfo.badInclude = true;
        }
    }
    foreach (ref sortedFile; mergedFiles)
    {
        auto filename = sortedFile.filename;
        auto fileInstanceInfo = childContext.getFileInstanceInfo(filename);

        Tree[] mergedTrees = sortedFile.mergedTrees;
        sortedFile.instances.length = fileInstanceInfo.instanceLocations.length;
        size_t numTranslationUnit;
        size_t numInTranslationUnit;
        RealFilename lastTU;
        bool anyRealInstance;
        immutable(Formula)* prevInstanceConditionUsed = rootContext.logicSystem.false_;
        foreach (i, l; fileInstanceInfo.instanceLocations)
        {
            immutable(LocationContext)* translationUnit = l;
            while (translationUnit.prev !is null)
                translationUnit = translationUnit.prev;

            sortedFile.instances[i].instanceConditionUsed
                = fileInstanceInfo.instanceConditionsUsed[i];
            sortedFile.instances[i].locationPrefix = l;
            sortedFile.instances[i].badInclude = fileInstanceInfo.badInclude;

            if (RealFilename(translationUnit.filename) != inputFile)
                continue;
            Context context = childContext;

            sortedFile.locConditions.merge(prevInstanceConditionUsed, *fileInstanceInfo.instanceLocConditions[i],
                    fileInstanceInfo.instanceConditionsUsed[i], rootContext.logicSystem);
            prevInstanceConditionUsed = rootContext.logicSystem.or(prevInstanceConditionUsed,
                    fileInstanceInfo.instanceConditionsUsed[i]);

            if (l !in context.locationContextInfoMap.locationContextInfos
                    || context.locationContextInfoMap.locationContextInfos[l].trees.entries.length
                    == 0)
            {
                continue;
            }

            if (fileInstanceInfo.badInclude)
                continue;

            SimpleClassAllocator!(CppParseTreeStruct*) savedGlobalAllocator = treeAllocator;
            scope (exit)
                treeAllocator = savedGlobalAllocator;
            SimpleClassAllocator!(CppParseTreeStruct*) savedAllocator = sortedFile.treeAllocator;
            SimpleClassAllocator!(CppParseTreeStruct*) newAllocator = new SimpleClassAllocator!(
                    CppParseTreeStruct*);
            sortedFile.treeAllocator = newAllocator;

            LocationContextInfo locationContextInfo = context
                .locationContextInfoMap.locationContextInfos[l];

            void mergeLocationContextInfos(LocationContextInfo locationContextInfo)
            {
                if (locationContextInfo.locationContext !is null && locationContextInfo.locationContext.name.among("^",
                        "#", "##") && locationContextInfo.condition !is null)
                {
                    treeAllocator = savedGlobalAllocator;
                    auto l2 = removeLocationPrefix(locationContextInfo.locationContext,
                            l.prev, context.locationContextMap);
                    auto info2 = sortedFile.locationContextInfoMap.getLocationContextInfo(l2);
                    immutable(Formula)* c2 = locationContextInfo.condition;
                    c2 = context.logicSystem.removeRedundant(c2,
                            sortedFile.instances[i].instanceConditionUsed);

                    immutable(LocationContext)* lastLocContext;
                    Tree sourceTokens2 = removeLocationPrefix(locationContextInfo.sourceTokens,
                            l.prev, context.locationContextMap,
                            sortedFile.instances[i].instanceConditionUsed,
                            rootContext.logicSystem,
                            childContext.fileInstanceInfos, &lastLocContext);

                    if (info2.condition is null)
                    {
                        info2.condition = c2;
                        info2.mappedInParam = locationContextInfo.mappedInParam;
                    }
                    else
                    {
                        assert((info2.sourceTokens.isValid) == (sourceTokens2.isValid));
                        if (info2.sourceTokens.isValid && sourceTokens2.isValid)
                            sourceTokens2 = mergeTrees(info2.sourceTokens, sourceTokens2,
                                    [info2.condition, c2], context.logicSystem,
                                    context.anyErrorCondition,
                                    context.logicSystem.true_, MergeFlags.none);
                        info2.condition = context.logicSystem.or(info2.condition, c2);
                        info2.mappedInParam = info2.mappedInParam
                            || locationContextInfo.mappedInParam;
                    }

                    treeAllocator = newAllocator;
                    info2.sourceTokens = deepCopyTree(sourceTokens2, context.logicSystem);
                }
                for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                        child = child.next)
                {
                    if (child.locationContext.name.length == 0)
                    {
                        if (RealFilename(
                                child.locationContext.filename) !in childContext.fileInstanceInfos)
                            continue;
                        if (!childContext.fileInstanceInfos[RealFilename(
                                    child.locationContext.filename)].badInclude)
                            continue;
                    }
                    mergeLocationContextInfos(child);
                }
            }

            mergeLocationContextInfos(locationContextInfo);

            treeAllocator = savedGlobalAllocator;

            if (lastTU != RealFilename(translationUnit.filename))
            {
                numTranslationUnit++;
                numInTranslationUnit = 0;
            }
            else
                numInTranslationUnit++;

            assert(numTranslationUnit == 1);

            sortedFile.numTranslationUnits = numTranslationUnit;

            immutable(Formula)* condition1 = context.logicSystem.true_;
            immutable(Formula)* condition2 = context.logicSystem.true_;
            if (numTranslationUnit > 1)
                condition1 = context.logicSystem.boundLiteral("@includetu:" ~ sortedFile.filename.name,
                        ">=", numTranslationUnit - 1);
            if (numInTranslationUnit > 0)
                condition2 = context.logicSystem.boundLiteral("@includex:" ~ sortedFile.filename.name,
                        ">=", numInTranslationUnit);
            immutable(Formula)* condition = context.logicSystem.and(condition1, condition2);

            foreach (k; 0 .. i)
                if (sortedFile.instances[k].instanceCondition !is null)
                {
                    if (sortedFile.instances[k].tuFile == RealFilename(translationUnit.filename))
                        sortedFile.instances[k].instanceCondition = context.logicSystem.and(
                                sortedFile.instances[k].instanceCondition, condition2.negated);
                    else
                        sortedFile.instances[k].instanceCondition = context.logicSystem.and(
                                sortedFile.instances[k].instanceCondition, condition1.negated);
                }
            sortedFile.instances[i].instanceCondition = condition;
            sortedFile.instances[i].tuFile = RealFilename(translationUnit.filename);
            sortedFile.instances[i].hasTree = true;
            sortedFile.instances[i].warnings = locationContextInfo.warnings;

            lastTU = sortedFile.instances[i].tuFile;

            sortedFile.locPrefixToInstance[l] = i;

            immutable(LocationContext)* lastLocContext;
            Tree[] trees;
            foreach (e; locationContextInfo.trees.entries)
            {
                trees.reserve(trees.length + e.data.length);
                foreach (tree; e.data)
                {
                    if (tree.start.context is null)
                        continue;
                    Tree tree2 = removeLocationPrefix(tree, l.prev, context.locationContextMap,
                            sortedFile.instances[i].instanceConditionUsed,
                            rootContext.logicSystem,
                            childContext.fileInstanceInfos, &lastLocContext);
                    trees ~= tree2;
                }
            }
            sortedFile.instances[i].mappedTrees = trees;

            if (!anyRealInstance)
                mergedTrees = trees;
            else
                mergedTrees = mergeArrays(mergedTrees, trees, [condition.negated, condition], context.logicSystem, context.anyErrorCondition,
                        context.logicSystem.true_, MergeFlags.none /*MergeFlags.nullOnTreeConditionRec*/ ,
                        4);

            treeAllocator = newAllocator;

            foreach (ref t; mergedTrees)
                t = deepCopyTree(t, context.logicSystem);

            foreach (t; mergedTrees)
                simplifyMergedConditions(t, rootContext.logicSystem/*, sortedFile.filename*/);

            if (l !in rootContext.locationContextInfoMap.locationContextInfos)
            {
                rootContext.locationContextInfoMap.locationContextInfos[l] = new LocationContextInfo;
                rootContext.locationContextInfoMap.locationContextInfos[l].warnings
                    = locationContextInfo.warnings;
            }

            anyRealInstance = true;
        }

        sortedFile.mergedTrees = mergedTrees;
    }

    writeln("mergeFiles trees ", sw.peek.total!"msecs", " ms");
    sw.reset();
}

void mergeFiles(Context rootContext, ref MergedFile[] mergedFiles, MergedFile[] mergedFiles2)
{
    if (mergedFiles.length == 0)
    {
        mergedFiles = mergedFiles2;
        return;
    }

    size_t k1, k2;

    MergedFile[] mergedFilesOut;
    while (k1 < mergedFiles.length || k2 < mergedFiles2.length)
    {
        MergedFile* mergedFile1, mergedFile2;
        if (k1 >= mergedFiles.length)
        {
            mergedFilesOut ~= MergedFile(mergedFiles2[k2].filename);
            mergedFile1 = &mergedFilesOut[$ - 1];
            mergedFile2 = &mergedFiles2[k2];
            k2++;
        }
        else if (k2 >= mergedFiles2.length)
        {
            mergedFilesOut ~= mergedFiles[k1];
            k1++;
            continue;
        }
        else if (mergedFiles[k1].filename == mergedFiles2[k2].filename)
        {
            mergedFilesOut ~= mergedFiles[k1];
            mergedFile1 = &mergedFilesOut[$ - 1];
            mergedFile2 = &mergedFiles2[k2];
            k1++;
            k2++;
        }
        else if (mergedFiles[k1].filename.name < mergedFiles2[k2].filename.name)
        {
            mergedFilesOut ~= mergedFiles[k1];
            k1++;
            continue;
        }
        else
        {
            assert(mergedFiles[k1].filename.name > mergedFiles2[k2].filename.name);
            mergedFilesOut ~= MergedFile(mergedFiles2[k2].filename);
            mergedFile1 = &mergedFilesOut[$ - 1];
            mergedFile2 = &mergedFiles2[k2];
            k2++;
        }

        auto filename = mergedFile1.filename;
        assert(mergedFile1.filename == mergedFile2.filename);

        immutable(Formula)* conditionUsed1 = rootContext.logicSystem.false_;
        immutable(Formula)* conditionUsed2 = rootContext.logicSystem.false_;
        foreach (i; 0 .. mergedFile1.instances.length)
            conditionUsed1 = rootContext.logicSystem.or(conditionUsed1,
                    mergedFile1.instances[i].instanceConditionUsed);
        foreach (i; 0 .. mergedFile2.instances.length)
            conditionUsed2 = rootContext.logicSystem.or(conditionUsed2,
                    mergedFile2.instances[i].instanceConditionUsed);

        if (mergedFile2.numTranslationUnits > 0)
        {
            if (mergedFile1.numTranslationUnits == 0)
            {
                mergedFile1.mergedTrees = mergedFile2.mergedTrees;
                mergedFile1.macroInstances = mergedFile2.macroInstances;
            }
            else
            {
                if (mergedFile2.numTranslationUnits > 1)
                {
                    foreach (c; mergedFile2.mergedTrees)
                        moveTUMergedConditions(c, rootContext.logicSystem,
                                filename, mergedFile1.numTranslationUnits);
                }

                /*foreach (i, ref inst; mergedFile1.instances)
                {
                    writeln("left  instance ", i, ": ", inst.hasTree, " ", (inst.instanceCondition is null)?"null":inst.instanceCondition.toString, " ", (inst.instanceConditionUsed is null)?"null":inst.instanceConditionUsed.toString);
                }
                foreach (i, ref inst; mergedFile2.instances)
                {
                    writeln("right instance ", i, ": ", inst.hasTree, " ", (inst.instanceCondition is null)?"null":inst.instanceCondition.toString, " ", (inst.instanceConditionUsed is null)?"null":inst.instanceConditionUsed.toString);
                }*/

                bool[immutable(Formula)*] usedVariables;
                void addVars(immutable(Formula)* f)
                {
                    if (f.type == FormulaType.and)
                    {
                        foreach (c; f.subFormulas)
                            addVars(c);
                    }
                    else
                    {
                        usedVariables[f] = true;
                    }
                }

                void addVarsTree(Tree t)
                {
                    if (!t.isValid)
                        return;
                    if (t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
                    {
                        auto ctree = t.toConditionTree;
                        foreach (f; ctree.conditions)
                            addVars(f);
                    }
                    foreach (c; t.childs)
                        addVarsTree(c);
                }

                foreach (t; mergedFile1.mergedTrees)
                    addVarsTree(t);
                foreach (t; mergedFile2.mergedTrees)
                    addVarsTree(t);
                bool isNeeded(immutable(Formula)* f)
                {
                    if (f in usedVariables)
                        return true;
                    return false;
                }

                immutable(Formula)* calcNeeded(immutable(Formula)* f)
                {
                    if (f.type == FormulaType.and)
                    {
                        immutable(Formula)* r = rootContext.logicSystem.true_;
                        foreach (c; f.subFormulas)
                        {
                            auto x = calcNeeded(c);
                            r = rootContext.logicSystem.and(r, x);
                        }
                        return r;
                    }
                    if (isNeeded(f))
                        return f;
                    return rootContext.logicSystem.true_;
                }

                immutable(Formula)* conditionNeeded1 = calcNeeded(conditionUsed1);
                immutable(Formula)* conditionNeeded2 = calcNeeded(conditionUsed2);
                immutable(Formula)* condition = rootContext.logicSystem.boundLiteral(
                        "@includetu:" ~ mergedFile1.filename.name,
                        ">=", mergedFile1.numTranslationUnits);
                mergedFile1.mergedTrees = mergeArrays(mergedFile1.mergedTrees, mergedFile2.mergedTrees,
                        [rootContext.logicSystem.or(rootContext.logicSystem.and(condition.negated, conditionNeeded1), rootContext.logicSystem.and(condition, conditionNeeded2.negated)),
                         rootContext.logicSystem.or(rootContext.logicSystem.and(condition, conditionNeeded2), rootContext.logicSystem.and(condition.negated, conditionNeeded1.negated))],
                        rootContext.logicSystem,/*anyErrorCondition*/
                        rootContext.logicSystem.false_,
                        rootContext.logicSystem.or(conditionNeeded1,
                            conditionNeeded2), MergeFlags.none /*MergeFlags.nullOnTreeConditionRec*/ ,
                        4);

                foreach (i; 0 .. mergedFile1.instances.length)
                    if (mergedFile1.instances[i].instanceCondition !is null)
                        mergedFile1.instances[i].instanceCondition = rootContext.logicSystem.and(
                                mergedFile1.instances[i].instanceCondition, condition.negated);
                foreach (i; 0 .. mergedFile2.instances.length)
                    if (mergedFile2.instances[i].instanceCondition !is null)
                    {
                        immutable(Formula)* f = mergedFile2.instances[i].instanceCondition;
                        if (mergedFile2.numTranslationUnits > 1)
                        {
                            f = moveTUMergedConditions(f, rootContext.logicSystem,
                                    filename, mergedFile1.numTranslationUnits);
                        }
                        mergedFile2.instances[i].instanceCondition = rootContext.logicSystem.and(f,
                                condition);
                    }

                size_t[immutable(LocationContext)*] locContextMap1;
                foreach (i, m; mergedFile1.macroInstances)
                    locContextMap1[m.locationContext] = i;

                foreach (i, m; mergedFile2.macroInstances)
                {
                    if (m.locationContext in locContextMap1)
                    {
                        auto k = locContextMap1[m.locationContext];

                        Tree sourceTokens2 = mergedFile1.macroInstances[k].sourceTokens;
                        assert((m.sourceTokens.isValid) == (sourceTokens2.isValid));
                        if (m.sourceTokens.isValid && sourceTokens2.isValid)
                            sourceTokens2 = mergeTrees(m.sourceTokens, sourceTokens2,
                                    [mergedFile1.macroInstances[k].condition, m.condition], rootContext.logicSystem, /*anyErrorCondition*/ rootContext.logicSystem.false_,
                                    rootContext.logicSystem.true_, MergeFlags.none);
                        mergedFile1.macroInstances[k].condition = rootContext.logicSystem.or(
                                mergedFile1.macroInstances[k].condition, m.condition);
                    }
                    else
                    {
                        locContextMap1[m.locationContext] = mergedFile1.macroInstances.length;
                        mergedFile1.macroInstances ~= m;
                    }
                }
            }

            SimpleClassAllocator!(CppParseTreeStruct*) savedGlobalAllocator = treeAllocator;
            scope (exit)
                treeAllocator = savedGlobalAllocator;
            SimpleClassAllocator!(CppParseTreeStruct*) savedAllocator = mergedFile1.treeAllocator;
            SimpleClassAllocator!(CppParseTreeStruct*) newAllocator = new SimpleClassAllocator!(
                    CppParseTreeStruct*);
            mergedFile1.treeAllocator = newAllocator;
            treeAllocator = newAllocator;

            foreach (ref t; mergedFile1.mergedTrees)
                t = deepCopyTree(t, rootContext.logicSystem);

            foreach (t; mergedFile1.mergedTrees)
                simplifyMergedConditions(t, rootContext.logicSystem/*, mergedFile1.filename*/);

            foreach (i, ref m; mergedFile1.macroInstances)
                m.sourceTokens = deepCopyTree(m.sourceTokens, rootContext.logicSystem);

            if (savedAllocator !is null)
                savedAllocator.clearAll();

            if (mergedFile2.treeAllocator !is null)
                mergedFile2.treeAllocator.clearAll();

            mergedFile1.numTranslationUnits += mergedFile2.numTranslationUnits;
        }

        mergedFile1.locConditions.merge(conditionUsed1,
                mergedFile2.locConditions, conditionUsed2, rootContext.logicSystem);

        foreach (i; 0 .. mergedFile2.instances.length)
        {
            mergedFile1.instances ~= mergedFile2.instances[i];
            if (mergedFile2.instances[i].badInclude)
                continue;
            mergedFile1.locPrefixToInstance[mergedFile1.instances[$ - 1].locationPrefix]
                = mergedFile1.instances.length - 1;
        }
    }
    mergedFiles = mergedFilesOut;
}

immutable(Formula)* simplifyMergedCondition(immutable(Formula)* f, LogicSystem logicSystem)
{
    static immutable(Formula)*[immutable(Formula)*] cache;

    if (f.type != FormulaType.and && f.type != FormulaType.or)
        return f;
    if (f.subFormulasLength == 0)
        return f;

    auto inCache = f in cache;
    if (inCache)
        return *inCache;

    immutable(Formula)*[immutable(Formula)*] variantConditions;

    foreach (combination; logicSystem.iterateAssignments())
    {
        auto f3 = replaceAll!((f2) {
            if (f2.type != FormulaType.and && f2.type != FormulaType.or
                && f2.data.name.startsWith("@include"))
            {
                if (combination.chooseVal(f2))
                    return logicSystem.true_;
                else
                    return logicSystem.false_;
            }
            else
                return f2;
        })(logicSystem, f);

        immutable(Formula)* currentCondition = logicSystem.true_;
        foreach (f4; combination.chosen)
            currentCondition = logicSystem.and(currentCondition, f4);

        if (f3 !in variantConditions)
            variantConditions[f3] = currentCondition;
        else
            variantConditions[f3] = logicSystem.or(variantConditions[f3], currentCondition);
    }

    immutable(Formula)* newCondition = logicSystem.false_;
    foreach (f1, f2; variantConditions)
        newCondition = logicSystem.or(newCondition, logicSystem.and(f1, f2));
    cache[f] = newCondition;
    return newCondition;
}

void simplifyMergedConditions(CppParseTree tree, LogicSystem logicSystem/*, RealFilename file*/)
{
    if (!tree.isValid)
        return;

    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            ctree.conditions[i] = simplifyMergedCondition(subTreeCondition, logicSystem);
        }
    }

    foreach (c; tree.childs)
    {
        simplifyMergedConditions(c, logicSystem/*, file*/);
    }
}

immutable(Formula)* moveTUMergedConditions(immutable(Formula)* condition,
        LogicSystem logicSystem, RealFilename file, size_t offset)
{
    auto f3 = replaceAll!((f2) {
        if (f2.type != FormulaType.and && f2.type != FormulaType.or
            && f2.data.name.startsWith("@include"))
        {
            return logicSystem.formula(f2.type, BoundLiteral(f2.data.name, f2.data.number + offset));
        }
        else
            return f2;
    })(logicSystem, condition);
    return f3;
}

void moveTUMergedConditions(Tree tree, LogicSystem logicSystem, RealFilename file, size_t offset)
{
    if (!tree.isValid)
        return;

    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            ctree.conditions[i] = moveTUMergedConditions(subTreeCondition,
                    logicSystem, file, offset);
        }
    }

    foreach (c; tree.childs)
    {
        moveTUMergedConditions(c, logicSystem, file, offset);
    }
}
