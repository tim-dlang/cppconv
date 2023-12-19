
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppconv;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.cppparallelparser;
import cppconv.cppparserwrapper;
import cppconv.cppsemantic1;
import cppconv.cppsemantic2;
import cppconv.cppsemantic;
import cppconv.cpptree;
import cppconv.cpptype;
import cppconv.dwriter;
import cppconv.ecs;
import cppconv.filecache;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.processing;
import cppconv.runcppcommon;
import cppconv.semanticmerging;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.parseexception;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.regex;
import std.stdio;
import std.typecons;

alias TypedefType = cppconv.cppsemantic.TypedefType;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

alias Location = LocationX;

alias ParserWrapper = cppconv.cppparserwrapper.ParserWrapper;

alias Context = cppconv.cppparallelparser.Context!(ParserWrapper);

alias Tree = CppParseTree;

int main(string[] args)
{
    treeAllocator = new SimpleClassAllocator!(CppParseTreeStruct*);
    preprocTreeAllocator = new SimpleClassAllocator!(CppParseTreeStruct*);
    globalLocationContextInfoAllocator = new SimpleClassAllocator!LocationContextInfo;
    globalStringPool._init(1024);

    RealFilename[] inputFiles;
    string outputPath;
    bool outputIsDir;
    Context context = new Context();
    InitialDefineSets initialDefineSets = new InitialDefineSets(context.logicSystem);
    context.defineSets = initialDefineSets;
    context.locationContextMap = new LocationContextMap();
    context.fileCache = new FileCache();
    DCodeOptions dCodeOptions;
    bool noSemantic = false;
    bool warnUnused = false;
    Tree[] initialConditions;

    string origCwd = getcwd();
    string movePath(string path)
    {
        if (path.startsWith("/"))
            return path;
        string r = buildNormalizedPath(relativePath(absolutePath(path, origCwd), getcwd()))
                .replace("\\", "/");
        return r;
    }

    for (size_t i = 1; i < args.length; i++)
    {
        string arg = args[i];
        if (arg.startsWith("-"))
        {
            if (arg == "--add-decl-comments")
                dCodeOptions.addDeclComments = true;
            else if (arg == "--no-decl-comments")
                dCodeOptions.addDeclComments = false;
            else if (arg == "--no-semantic")
                noSemantic = true;
            else if (arg == "--warn-unused")
                warnUnused = true;
            else if (arg == "--ignore-missing-include-path")
                context.ignoreMissingIncludePath = true;
            else if (arg == "--include-all-decls")
                dCodeOptions.includeAllDecls = true;
            else if (arg == "--builtin-cpp-types")
                dCodeOptions.builtinCppTypes = true;
            else if (arg == "--base-dir")
            {
                i++;
                chdir(args[i]);
                writeln("--base-dir ", args[i]);
                writeln("  origCwd ", origCwd);
                writeln("  getcwd ", getcwd());
            }
            else if (arg == "-I")
            {
                i++;
                string path = movePath(args[i]);
                if (!context.ignoreMissingIncludePath)
                    enforce(std.file.exists(path) && std.file.isDir(path),
                            text("include path does not exist \"", path, "\""));
                context.fileCache.includeDirs ~= IncludeDir(path, context.logicSystem.true_);
            }
            else if (arg.startsWith("-I"))
            {
                string path = movePath(arg[2 .. $]);
                if (!context.ignoreMissingIncludePath)
                    enforce(std.file.exists(path) && std.file.isDir(path),
                            text("include path does not exist \"", path, "\""));
                context.fileCache.includeDirs ~= IncludeDir(path, context.logicSystem.true_);
            }
            else if (arg.startsWith("-include"))
            {
                i++;
                context.fileCache.alwaysIncludeFiles ~= RealFilename(movePath(args[i]));
            }
            else if (arg == "--extra-output-str")
            {
                i++;
                context.extraOutputStr = args[i];
            }
            else if (arg == "--spaces")
            {
                i++;
                dCodeOptions.indent = repeatChar!' '(to!size_t(args[i]));
            }
            else if (arg == "--config-module")
            {
                i++;
                dCodeOptions.configModule = args[i];
            }
            else if (arg == "--helper-module")
            {
                i++;
                dCodeOptions.helperModule = args[i];
            }
            else if (arg.startsWith("--condition"))
            {
                i++;

                LocationX location = LocationX(LocationN(), new immutable(LocationContext)(null,
                        LocationN(), LocationN.LocationDiff(), "", "@cmdline", true));

                Tree tree;
                try
                {
                    tree = preprocParseTokenList(args[i], location,
                            preprocTreeAllocator, &globalStringPool);
                }
                catch (ParseException e)
                {
                    stderr.writeln("Condition ", args[i], " ============");
                    throw e;
                }
                initialConditions ~= tree;
            }
            else if (arg.startsWith("-U"))
            {
                string def = arg[2 .. $];
                enforce(def.length);
                bool isRegex;
                foreach (dchar c; def)
                {
                    if (!c.inCharSet!"a-zA-Z0-9_")
                        isRegex = true;
                }
                if (isRegex)
                    initialDefineSets.addUndefRegex(def);
                else
                    initialDefineSets.getDefineSet(def)
                        .updateUndef(context.logicSystem, context.logicSystem.true_);
            }
            else if (arg.startsWith("-D"))
            {
                auto parts = arg[2 .. $].split("=");
                if (parts.length == 1)
                    parts ~= "";
                if (parts.length != 2)
                {
                    stderr.writeln("wrong argument ", arg);
                    return 1;
                }
                Location loc = LocationX(LocationN(), context.getLocationContext(immutable(LocationContext)(null,
                        LocationN(), LocationN.LocationDiff(), "", "cmdline")));
                Tree[] childs;
                childs ~= Tree.init;
                childs ~= Tree.init;
                childs ~= Tree.init;
                childs ~= Tree.init;
                childs ~= Tree.init;
                childs ~= Tree(parts[0], SymbolID.max, ProductionID.max, NodeType.token, []);
                childs ~= Tree(" ", SymbolID.max, ProductionID.max, NodeType.token, []);
                Tree content = Tree(parts[1], SymbolID.max, ProductionID.max, NodeType.token, []);
                content.setStartEnd(loc, loc);
                auto grammarInfo = getDummyGrammarInfo("Token");
                Tree token = Tree("Token", grammarInfo.startNonterminalID,
                        grammarInfo.startProductionID, NodeType.nonterminal, [content]);
                token.grammarInfo = grammarInfo;
                token.setStartEnd(loc, loc);
                childs ~= Tree("[]", SymbolID.max, ProductionID.max, NodeType.array, [token]);
                grammarInfo = getDummyGrammarInfo("VarDefine");
                Tree definition = Tree("VarDefine", grammarInfo.startNonterminalID,
                        grammarInfo.startProductionID, NodeType.nonterminal, childs);
                definition.grammarInfo = grammarInfo;
                definition.setStartEnd(loc, loc);

                context.defineSets.getDefineSet(parts[0]).update(context.logicSystem,
                        context.logicSystem.true_, false, definition);
            }
            else if (arg == "--output-file")
            {
                i++;
                outputPath = args[i];
                outputIsDir = false;
            }
            else if (arg == "--output-dir")
            {
                i++;
                outputPath = args[i];
                outputIsDir = true;
            }
            else if (arg.startsWith("--output-config"))
            {
                i++;
                dCodeOptions.readConfig(args[i]);
            }
            else
            {
                stderr.writeln("unknown argument ", arg);
                return 1;
            }
        }
        else
        {
            inputFiles ~= RealFilename(movePath(arg));
        }
    }

    context.fileCache.origIncludeDirsSize = context.fileCache.includeDirs.length;

    if (inputFiles.length < 1)
    {
        stderr.writeln("missing input file");
        return 1;
    }

    context.fileCache.files[RealFilename("")] = null;
    context.fileCache.files.remove(RealFilename(""));

    context.getFileInstanceInfo(RealFilename("@@@")).badInclude = true;

    MergedFile[] mergedFiles;
    string[immutable(Formula)*] mergedAliasMap;
    foreach (inputFile; inputFiles)
    {
        auto savedAllocator = treeAllocator;
        auto tmpAllocator = new SimpleClassAllocator!(CppParseTreeStruct*);
        treeAllocator = tmpAllocator;
        Context context2;
        Semantic semantic;
        processMainFile(context, inputFile, context2, semantic,
                noSemantic, initialConditions, warnUnused);

        if (warnUnused)
        {
            foreach (d; context.fileCache.includeDirs)
            {
                if (!d.used)
                {
                    writeln("Warning: Unused include path: ", d.path);
                }
            }
        }

        context.fileCache.includeDirs
            = context.fileCache.includeDirs[0 .. context.fileCache.origIncludeDirsSize];

        destroy(semantic);
        semantic = null;

        MergedFile[] mergedFiles2;
        mergeFiles(context, inputFile, context2, mergedFiles2);
        foreach (ref m; mergedFiles2)
        {
            void collectMacroInstances(LocationContextInfo locationContextInfo)
            {
                if (locationContextInfo.locationContext !is null && locationContextInfo.locationContext.name.among("^",
                        "#", "##") && locationContextInfo.condition !is null)
                {
                    m.macroInstances ~= MacroInstanceInfo(locationContextInfo.locationContext,
                            locationContextInfo.condition,
                            locationContextInfo.sourceTokens, locationContextInfo.mappedInParam);
                }
                for (LocationContextInfo child = locationContextInfo.firstChild; child !is null;
                        child = child.next)
                {
                    collectMacroInstances(child);
                }
            }

            collectMacroInstances(m.locationContextInfoMap.getLocationContextInfo(null));
        }

        if (mergedFiles.length == 0)
        {
            mergedFiles = mergedFiles2;
        }
        else
        {
            mergeFiles(context, mergedFiles, mergedFiles2);
            foreach (ref m; mergedFiles2)
                m.locationContextInfoMap.clear();
            (cast(ubyte[]) mergedFiles2)[] = 0;
        }

        foreach (c, def; context2.defineSets.aliasMap)
        {
            if (c in mergedAliasMap)
                enforce(mergedAliasMap[c] == def);
            else
                mergedAliasMap[c] = def;
        }

        treeAllocator = savedAllocator;
        tmpAllocator.clearAll();
        destroy(context2);
        context2 = null;

        context.logicSystem.impliesCache = null;
        context.logicSystem.simplifyCache = null;
        context.logicSystem.andCache = null;
        context.logicSystem.removeRedundantCache = null;
        context.logicSystem.distributeOrSimpleCache = null;
        context.logicSystem.filterImpliedCache = null;
    }

    if (warnUnused)
    {
        foreach (name; initialDefineSets.undefRegexUsed.sortedKeys)
        {
            if (!initialDefineSets.undefRegexUsed[name])
                writeln("Warning: Unused undef regex: ", name);
        }
    }

    {
        context.fileCache.alwaysIncludeFiles.length = 0; // should not be needed any more

        MergedFile*[RealFilename] mergedFileByName;
        foreach (ref m; mergedFiles)
        {
            mergedFileByName[m.filename] = &m;
        }

        Semantic mergedSemantic = new Semantic();
        mergedSemantic.entityManager = new EntityManager(10_000_000);
        mergedSemantic.componentExtraInfo = new ComponentManager!TreeExtraInfo(
                mergedSemantic.entityManager);
        mergedSemantic.logicSystem = context.logicSystem;
        mergedSemantic.locationContextMap = context.locationContextMap;
        mergedSemantic.mergedFileByName = mergedFileByName;
        mergedSemantic.rootScope = new Scope(Tree.init, mergedSemantic.logicSystem.true_);
        if (!noSemantic)
        {
            {
                foreach (inputFileId, inputFile; inputFiles)
                {
                    auto semantic2 = genSemantic(context, inputFile, mergedFileByName);

                    mergeSemantics(mergedSemantic, semantic2, [inputFile], mergedFiles);

                    semantic2.treeToID.clear();
                    semantic2.entityManager.clear();
                    semantic2.declarationCache.clear();
                    semantic2.treesVisited.clear();
                    semantic2.rootScope.childScopeByTree.clear();
                    semantic2.rootScope.subScopes.clear();
                    destroy(semantic2.rootScope);
                    destroy(semantic2);

                    context.logicSystem.impliesCache = null;
                    context.logicSystem.simplifyCache = null;
                    context.logicSystem.andCache = null;
                    context.logicSystem.removeRedundantCache = null;
                    context.logicSystem.distributeOrSimpleCache = null;
                    context.logicSystem.filterImpliedCache = null;
                }
            }

            foreach (ref sortedFile; mergedFiles)
            {
                void setTreeParent(Tree tree, Tree parent)
                {
                    if (!tree.isValid)
                        return;
                    mergedSemantic.extraInfo(tree).parent = parent;
                    foreach (i; 0 .. tree.childs.length)
                        setTreeParent(tree.childs[i], tree);
                }

                Tree[] mergedTrees = sortedFile.mergedTrees;

                foreach (tree; mergedTrees)
                {
                    setTreeParent(tree, Tree.init);
                }
            }
            mergedSemantic.componentExtraInfo2 = new ComponentManager!TreeExtraInfo2(
                    mergedSemantic.entityManager);
            foreach (ref mergedFile; mergedFiles)
            {
                foreach (t; mergedFile.mergedTrees)
                    runSemantic2(mergedSemantic, t, Tree.init, mergedSemantic.logicSystem.true_);
            }
        }

        if (!noSemantic)
        {
            foreach (ref m; mergedFiles)
            {
                m.locationContextInfoMap.allocator = globalLocationContextInfoAllocator;
                foreach (x; m.macroInstances)
                {
                    auto info = m.locationContextInfoMap.getLocationContextInfo(x.locationContext);
                    info.condition = x.condition;
                    info.sourceTokens = x.sourceTokens;
                    info.mappedInParam = x.mappedInParam;
                }
                Tree[] arr;
                foreach (x; m.mergedTrees)
                    if (x.isValid)
                        arr ~= x;
                if (arr.length)
                {
                    Tree tmp = createArrayTree(arr);
                    normalizeLocations(tmp);
                    buildLocations(context, m.locationContextInfoMap, tmp,
                            context.logicSystem.true_, mergedSemantic);
                }

                m.locationContextInfoMap.sortTree();
            }
        }

        if (!noSemantic)
        {
            if (outputPath.length)
            {
                writeAllDCode(outputPath, outputIsDir, dCodeOptions, mergedSemantic,
                        context.fileCache, inputFiles, mergedFiles, mergedAliasMap, warnUnused);
            }
        }
    }

    return 0;
}

Semantic genSemantic(Context context, RealFilename inputFile,
        MergedFile*[RealFilename] mergedFileByName)
{
    Semantic semantic2 = new Semantic();
    semantic2.entityManager = new EntityManager(10_000_000);
    semantic2.componentExtraInfo = new ComponentManager!TreeExtraInfo(semantic2.entityManager);
    semantic2.logicSystem = context.logicSystem;
    semantic2.locationContextMap = context.locationContextMap;
    semantic2.rootScope = new Scope(Tree.init, context.logicSystem.true_);
    semantic2.rootScope.initialized = true;
    semantic2.mergedFileByName = mergedFileByName;
    semantic2.isCPlusPlus = inputFile.name.endsWith(".cpp");

    import std.datetime.stopwatch;

    auto sw = StopWatch(AutoStart.no);
    sw.start();
    writeln("==================== start semantic \"", inputFile.name, "\" ==========================");
    SemanticRunInfo semanticRun;
    semanticRun.semantic = semantic2;
    semanticRun.currentScope = semantic2.rootScope;
    semanticRun.afterMerge = true;

    semanticRun.currentFile = context.getLocationContext(immutable(LocationContext)(null,
            LocationN(), LocationN.LocationDiff(), "", inputFile.name));
    runSemanticFile(semanticRun, semanticRun.currentFile);
    sw.stop();
    writeln("==================== end semantic \"", inputFile.name, "\" ========================== ", sw.peek.total!"msecs", " ms");
    return semantic2;
}
