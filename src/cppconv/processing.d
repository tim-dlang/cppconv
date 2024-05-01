
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.processing;
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
import cppconv.runcppcommon;
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

private alias Context = cppconv.cppparallelparser.Context!(ParserWrapper);

bool processFile(RealFilename filename, Context context, immutable Formula* condition,
        ref ParallelParser!(ParserWrapper) parallelParser,
        immutable(LocationContext)* locationContext)
in
{
    assert(!parallelParser.droppedParser);
}
out
{
    assert(!parallelParser.droppedParser);
}
do
{
    FileData fileData = context.fileCache.getFile(filename);
    assert(fileData.startLocation.context.filename == locationContext.filename);

    if (fileData.notFound)
    {
        return false;
    }

    context.fileIncludeDepth[filename]++;
    scope (exit)
        context.fileIncludeDepth[filename]--;

    if (context.fileIncludeDepth[filename] > 50)
        throw new Exception(text("inclusion too deep ", filename));

    Tree tree = fileData.tree;

    assert(tree.nonterminalID == preprocNonterminalIDFor!"PreprocessingFile");
    assert(tree.childs.length == 1);
    Tree[] lines = tree.childs[0].childs;

    LocConditions* locConditions = new LocConditions;
    if (context.addLocationInstances)
    {
        auto fileInstanceInfo = context.getFileInstanceInfo(filename);
        fileInstanceInfo.instanceLocations ~= locationContext;
        fileInstanceInfo.instanceConditions ~= condition;
        if (fileInstanceInfo.usedCondition is null)
            fileInstanceInfo.usedCondition = condition;
        else
            fileInstanceInfo.usedCondition = context.logicSystem.or(
                    fileInstanceInfo.usedCondition, condition);

        Tree singleLine;
        foreach (line; lines)
        {
            if (line.nonterminalID == preprocNonterminalIDFor!"Conditional"
                    && line.childs[2].nonterminalID == preprocNonterminalIDFor!"PPEndif"
                    && line.childs[1].childs.length == 1
                    && line.childs[1].childs[0].nonterminalID == preprocNonterminalIDFor!"PPError")
                continue; // For /usr/include/bits/stat.h
            if (line.nonterminalID == preprocNonterminalIDFor!"EmptyLine")
                continue;

            if (singleLine.isValid)
            {
                singleLine = Tree.init;
                break;
            }
            singleLine = line;
        }

        immutable(Formula)* conditionUsed = condition;
        if (singleLine.isValid && singleLine.nonterminalID == preprocNonterminalIDFor!"Conditional"
                && singleLine.childs[2].nonterminalID == preprocNonterminalIDFor!"PPEndif")
        {
            auto newCondition = preprocIfToCondition!(ParserWrapper)(singleLine,
                    locationContext, condition, context.logicSystem, context.defineSets);
            conditionUsed = context.logicSystem.and(newCondition, condition);
        }

        fileInstanceInfo.instanceConditionsUsed ~= conditionUsed;
        fileInstanceInfo.instanceLocConditions ~= locConditions;
    }

    processLines(lines, locationContext, context, condition, parallelParser, *locConditions);
    return true;
}

void processLines(Tree[] lineTrees, immutable(LocationContext)* locationContext,
        Context context, immutable Formula* condition,
        ref ParallelParser!(ParserWrapper) parallelParser, ref LocConditions locConditions)
in
{
    assert(!parallelParser.droppedParser);
}
out
{
    assert(!parallelParser.droppedParser);
}
do
{
    foreach (lineNr, l; lineTrees)
    {
        if (l.nonterminalID.among(preprocNonterminalIDFor!"EmptyLine",
                preprocNonterminalIDFor!"EmptyDirective"))
        {
            locConditions.add(l.start.loc, l.end.loc, condition);
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"TextLine")
        {
            locConditions.add(l.start.loc, l.end.loc, condition);
            foreach (tokenNr, t; l.childs[1].childs)
            {
                bool isNextParen;
                if (tokenNr + 1 < l.childs[1].childs.length)
                {
                    if (l.childs[1].childs[tokenNr + 1].childs[0].content == "(")
                        isNextParen = true;
                }
                else if (lineNr + 1 < lineTrees.length
                        && lineTrees[lineNr + 1].nonterminalID == preprocNonterminalIDFor!"TextLine"
                        && lineTrees[lineNr + 1].childs[1].childs.length >= 1
                        && lineTrees[lineNr + 1].childs[1].childs[0].childs[0].content == "(")
                {
                    isNextParen = true;
                }
                bool[string] macrosDone;

                processToken!(ParserWrapper)(reparentLocation(t.start,
                        locationContext), t, context, condition, parallelParser,
                        isNextParen, null, Location.invalid, macrosDone, null, false);
            }
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"Include"
                || l.nonterminalID == preprocNonterminalIDFor!"IncludeNext")
        {
            assert(l.childs[1].content == "#");
            assert(l.childs[3].content == "include" || l.childs[3].content == "include_next");
            assert(l.childs[4].nonterminalID == preprocNonterminalIDFor!"HeaderPart");
            assert(l.childs[4].childs[1].nonterminalID == preprocNonterminalIDFor!"HeaderName");

            locConditions.add(l.start.loc, l.end.loc, condition);

            Tree nameToken = l.childs[4].childs[1].childs[0];
            string nextFile = nameToken.content;

            static string includeIndent;
            includeIndent ~= "  ";
            scope (exit)
                includeIndent = includeIndent[0 .. $ - 2];

            immutable(Formula)* conditionNotProcessed = condition;
            Tuple!(RealFilename, immutable(Formula)*)[] realFilenames;
            if ((nextFile.startsWith("\"") && nextFile.endsWith("\""))
                    || (nextFile.startsWith("<") && nextFile.endsWith(">")))
            {
                auto filename2 = VirtualFilename(nextFile[1 .. $ - 1]);
                if (l.childs[3].content == "include")
                    realFilenames = context.fileCache.lookupFilename(filename2, RealFilename(nextFile.startsWith("\"")
                            ? locationContext.filename : ""), condition, context.logicSystem);
                else if (l.childs[3].content == "include_next")
                    realFilenames = context.fileCache.lookupFilenameNext(filename2,
                            RealFilename(locationContext.filename), condition, context.logicSystem);
            }
            foreach (realFilenameAndCondition; realFilenames)
            {
                conditionNotProcessed = context.logicSystem.and(conditionNotProcessed,
                        realFilenameAndCondition[1].negated);
            }
            ParallelParser!(ParserWrapper) parallelParserNotProcessed;
            if (!conditionNotProcessed.isFalse || realFilenames.length == 0)
                parallelParserNotProcessed = parallelParser.forkLazy();
            ParallelParser!(ParserWrapper)[] parallelParsersIncludes;
            parallelParsersIncludes.length = realFilenames.length;
            foreach (i, realFilenameAndCondition; realFilenames)
            {
                parallelParsersIncludes[i] = parallelParser.forkLazy();
            }
            parallelParser.removeReference(null);
            foreach (i, realFilenameAndCondition; realFilenames)
            {
                bool includeProcessed;
                auto realFilename = realFilenameAndCondition[0];
                auto nameLoc = reparentLocation(nameToken.start, locationContext);
                immutable(LocationContext)* locationContext2 = context.getLocationContext(
                        immutable(LocationContext)(nameLoc.context,
                        nameLoc.loc, nameToken.inputLength, "", realFilename.name));

                parallelParsersIncludes[i].terminateFuncMacros(realFilenameAndCondition[1], null);
                tryMergeParser!(ParserWrapper)(parallelParsersIncludes[i],
                        realFilenameAndCondition[1], context, null);

                if (!includeProcessed && processFile(realFilename, context,
                        realFilenameAndCondition[1], parallelParsersIncludes[i], locationContext2))
                {
                    includeProcessed = true;

                    parallelParsersIncludes[i].terminateFuncMacros(realFilenameAndCondition[1],
                            null);
                    tryMergeParser!(ParserWrapper)(parallelParsersIncludes[i],
                            realFilenameAndCondition[1], context, null);
                }
                if (!includeProcessed)
                {
                    conditionNotProcessed = context.logicSystem.or(conditionNotProcessed,
                            realFilenameAndCondition[1]);
                    if (parallelParserNotProcessed is null)
                        parallelParserNotProcessed = parallelParsersIncludes[i];
                    else
                        parallelParsersIncludes[i].removeReference(null);
                    parallelParsersIncludes[i] = null;
                }
            }
            parallelParser = null;

            if (parallelParserNotProcessed !is null)
            {
                if (!conditionNotProcessed.isFalse)
                {
                    string warningText = "WARNING: could not find ";
                    foreach (c; l.childs)
                        if (c.childs.length
                                && c.nonterminalID == preprocNonterminalIDFor!"HeaderPart")
                            warningText ~= c.childs[1].childs[0].content;
                        else if (c.childs.length)
                            warningText ~= c.childs[0].content;
                        else
                            warningText ~= c.nameOrContent;
                    context.addWarning(reparentLocation(l.start,
                            locationContext), conditionNotProcessed, warningText);
                }

                // pretend any unresolved include is a declaration
                string newText = "@#IncludeDecl ";
                foreach (c; l.childs)
                    if (c.childs.length && c.nonterminalID == preprocNonterminalIDFor!"HeaderPart")
                        newText ~= c.childs[1].childs[0].content;
                    else if (c.childs.length)
                        newText ~= c.childs[0].content;
                    else
                        newText ~= c.nameOrContent;
                newText ~= "\n";
                Tree newToken = Tree(newText, SymbolID.max, ProductionID.max, NodeType.token, []);
                auto locationContextX = context.getLocationContext(immutable(LocationContext)(locationContext,
                        l.start.loc, l.inputLength, "@#IncludeDecl", l.start.context.filename));
                auto newStart = reparentLocation(l.start, locationContextX);
                auto newEnd = reparentLocation(l.end, locationContextX);
                newToken.setStartEnd(newStart, newEnd);
                processDirectToken!(ParserWrapper)(newToken.start, newToken, context,
                        parallelParserNotProcessed, conditionNotProcessed, null, false, null);
            }

            ParallelParser!(ParserWrapper)[] parallelParsers;
            immutable(Formula)*[] conditionsParsers;

            foreach (i, realFilenameAndCondition; realFilenames)
            {
                if (parallelParsersIncludes[i] !is null)
                {
                    parallelParsers ~= parallelParsersIncludes[i];
                    conditionsParsers ~= realFilenameAndCondition[1];
                }
            }
            if (parallelParserNotProcessed !is null)
            {
                parallelParsers ~= parallelParserNotProcessed;
                conditionsParsers ~= conditionNotProcessed;
            }

            if (parallelParsers.length == 1)
            {
                parallelParser = parallelParsers[0];
            }
            else
            {
                parallelParser = new DoubleParallelParser!ParserWrapper(context,
                        parallelParsers, conditionsParsers);
                foreach (p; parallelParsers)
                {
                    p.removeReference(null);
                }
            }
            tryMergeParser!(ParserWrapper)(parallelParser, condition, context, null);
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"AddIncludePath")
        {
            assert(l.childs[1].content == "#");
            assert(l.childs[3].content == "addincludepath");

            locConditions.add(l.start.loc, l.end.loc, condition);

            string path = l.childs[5].content[1 .. $ - 1];
            if (!isAbsolute(path))
            {
                path = absolutePath(path, dirName(absolutePath(locationContext.filename)));
                if (!isAbsolute(locationContext.filename))
                {
                    path = relativePath(path);
                }
            }

            if (!context.ignoreMissingIncludePath)
                enforce(std.file.exists(path) && std.file.isDir(path),
                        text("include path does not exist \"", path,
                            "\" location: ", locationStr(l.start)));

            context.fileCache.includeDirs ~= IncludeDir(path, condition);
        }
        else if (l.name.among("VarDefine", "FuncDefine", "Undef", "LockDefine",
                "AliasDefine", "Unknown", "RegexUndef", "Imply"))
        {
            locConditions.add(l.start.loc, l.end.loc, condition);
            updateDefineSet!ParserWrapper(context.defineSets, condition, l);
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"PPError")
        {
            locConditions.add(l.start.loc, l.end.loc, condition);

            SingleParallelParser!(ParserWrapper) singleParser = new SingleParallelParser!(
                    ParserWrapper)(context);
            singleParser.errorNodes ~= Tree("#error " ~ "TODO PPError",
                    SymbolID.max, ProductionID.max, NodeType.token, []);
            parallelParser.removeReference(null);
            parallelParser = singleParser;
            context.addError(reparentLocation(l.start, locationContext), condition, "#error");
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"PPWarning")
        {
            locConditions.add(l.start.loc, l.end.loc, condition);

            context.addWarning(reparentLocation(l.start, locationContext), condition, "#warning");
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"Conditional")
        {
            ParallelParser!(ParserWrapper) visitConditional(Location currentStart, Tree x, immutable(Formula)* condition,
                    immutable(Formula)* conditionDone,
                    ref ParallelParser!(ParserWrapper) parallelParser2)
            in
            {
                assert(!parallelParser2.droppedParser);
            }
            out (r)
            {
                assert(!r.droppedParser);
            }
            do
            {
                context.checkReferences();
                if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIfDef"
                        || x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIfNDef"
                        || x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIf"
                        || x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPElif")
                {
                    locConditions.add(x.childs[0].start.loc, x.childs[0].end.loc, condition);
                    ParallelParser!(ParserWrapper) parallelParser3 = parallelParser2.forkLazy();

                    immutable(Formula)* newCondition, newCondition2, conditionHere,
                        conditionElse, conditionElse2, conditionHereWithContext;
                    with (context.logicSystem)
                    {
                        newCondition = preprocIfToCondition!(ParserWrapper)(x, locationContext,
                                and(condition, not(conditionDone)), context.logicSystem, context.defineSets);

                        newCondition2 = simplify(and(newCondition, not(conditionDone)));
                        conditionHere = simplify(and(condition, newCondition2));
                        //conditionHereWithContext = and(conditionHere, definesFormula);
                        conditionDone = simplify(distributeOrSimple(conditionDone, newCondition));
                        conditionElse = simplify(not(conditionDone));
                        conditionElse2 = simplify(and(condition, conditionElse));
                    }
                    string replacedCondition = x.childs[0].childs[3].content;
                    if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPElif")
                        replacedCondition = "if";

                    assert(context.existingTopParsers.canFind(parallelParser2));
                    assert(context.existingTopParsers.canFind(parallelParser3));

                    parallelParser2 = parallelParser2.filterParser(context.logicSystem,
                            conditionHere, false, null);
                    parallelParser3 = parallelParser3.filterParser(context.logicSystem,
                            conditionElse2, false, null);

                    assert(context.existingTopParsers.canFind(parallelParser2));
                    assert(context.existingTopParsers.canFind(parallelParser3));

                    if (conditionHere !is context.logicSystem.false_ /* || newCondition is context.logicSystem.false_*/ )
                        processLines(x.childs[1].childs, locationContext,
                                context, conditionHere, parallelParser2, locConditions);
                    else if (x.childs[1].inputLength > LocationN.LocationDiff.init)
                        locConditions.add(x.childs[1].start.loc,
                                x.childs[1].end.loc, conditionHere);

                    assert(context.existingTopParsers.canFind(parallelParser2));
                    assert(context.existingTopParsers.canFind(parallelParser3));

                    parallelParser3 = visitConditional(x.childs[$ - 1].start,
                            x.childs[$ - 1], condition, conditionDone, parallelParser3);
                    context.checkReferences();
                    ParallelParser!(ParserWrapper) r = new DoubleParallelParser!(ParserWrapper)(context,
                            parallelParser2, conditionHere,
                            parallelParser3, conditionElse2);
                    parallelParser2.removeReference(null);
                    parallelParser3.removeReference(null);
                    r = r.filterParser(context.logicSystem, condition, false, null);

                    context.checkReferences();
                    return r;
                }
                else if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPElse")
                {
                    locConditions.add(x.childs[0].start.loc, x.childs[0].end.loc, condition);
                    immutable(Formula)* newCondition2, conditionHere;
                    with (context.logicSystem)
                    {
                        newCondition2 = simplify(not(conditionDone));
                        conditionHere = simplify(and(condition, newCondition2));
                    }

                    if (conditionHere !is context.logicSystem.false_ /* || conditionDone is context.logicSystem.true_*/ )
                        processLines(x.childs[1].childs, locationContext,
                                context, conditionHere, parallelParser2, locConditions);
                    else if (x.childs[1].inputLength > LocationN.LocationDiff.init)
                        locConditions.add(x.childs[1].start.loc,
                                x.childs[1].end.loc, conditionHere);
                    assert(x.childs[$ - 1].nonterminalID == preprocNonterminalIDFor!"PPEndif");
                    assert(x.childs[$ - 1].nonterminalID == preprocNonterminalIDFor!"PPEndif");
                    context.checkReferences();
                    locConditions.add(x.childs[$ - 1].start.loc, x.childs[$ - 1].end.loc, condition);
                    return parallelParser2;
                }
                else if (x.nonterminalID == preprocNonterminalIDFor!"PPEndif")
                {
                    locConditions.add(x.start.loc, x.end.loc, condition);
                    return parallelParser2;
                }
                else
                {
                    assert(false, text("TODO: Conditional: ", x.childs[0].toString));
                }
            }

            context.checkReferences();

            parallelParser = visitConditional(l.start, l, condition,
                    context.logicSystem.false_, parallelParser);
            context.checkReferences();

            tryMergeParser!(ParserWrapper)(parallelParser, condition, context, null);
            context.checkReferences();
        }
        else if (l.nonterminalID == preprocNonterminalIDFor!"Pragma")
        {
            locConditions.add(l.start.loc, l.end.loc, condition);

            string content = "\"";
            foreach (t; l.childs[5].childs)
            {
                foreach (char c; t.childs[0].content)
                {
                    if (c == '\\')
                        content ~= "\\\\";
                    else if (c == '\"')
                        content ~= "\\\"";
                    else
                        content ~= c;
                }
            }
            content ~= "\"";
            foreach (tok; ["_Pragma", "(", content, ")"])
            {
                bool isNextParen;
                bool[string] macrosDone;
                Tree t = Tree(tok, SymbolID.max, ProductionID.max, NodeType.token, []);
                auto grammarInfo = getDummyGrammarInfo("Token");
                t.grammarInfo = grammarInfo;
                t.setStartEnd(l.start, l.start);
                Tree t2 = Tree("Token", grammarInfo.startNonterminalID,
                        grammarInfo.startProductionID, NodeType.nonterminal, [t]);
                t2.grammarInfo = grammarInfo;
                t2.setStartEnd(l.start, l.start);
                processToken!(ParserWrapper)(reparentLocation(l.start,
                        locationContext), t2, context, condition, parallelParser,
                        isNextParen, null, Location.invalid, macrosDone, null, false);
            }
        }
        else
        {
            locConditions.add(l.start.loc, l.end.loc, condition);

            writeln("TODO: ", l.toString);
        }
    }
}

void processMainFile(Context rootContext, RealFilename inputFile, ref Context context2,
        ref Semantic outSemantic, bool noSemantic,
        Tree[] initialConditions, bool warnUnused)
{
    context2 = new Context(rootContext.logicSystem, rootContext.defineSets.dup);
    context2.fileCache = rootContext.fileCache;
    context2.extraOutputStr = rootContext.extraOutputStr;
    context2.extraOutputDir = rootContext.extraOutputDir;
    context2.locationContextMap = rootContext.locationContextMap;
    context2.isCPlusPlus = inputFile.name.endsWith(".cpp");
    context2.addLocationInstances = true;
    context2.getFileInstanceInfo(RealFilename("@@@")).badInclude = true;
    context2.ignoreMissingIncludePath = rootContext.ignoreMissingIncludePath;

    Semantic semantic;
    context2.defineConditions = rootContext.defineConditions;
    context2.undefConditions = rootContext.undefConditions;
    context2.unknownConditions = rootContext.unknownConditions;
    processMainFile(inputFile, context2, semantic, noSemantic, initialConditions);
    outSemantic = semantic;

    if (warnUnused)
    {
        foreach (name; context2.defineSets.defineSets.sortedKeys)
        {
            auto d = context2.defineSets.defineSets[name];
            if (d.beforeMainFile && !d.used)
            {
                writeln("Warning: Macro ", name, " is not used");
            }
        }
    }
}

void processMainFile(RealFilename inputFile, Context context,
        ref Semantic outSemantic, bool noSemantic, Tree[] initialConditions)
{
    writeln("========= processMainFile ", inputFile, " ===============");

    SingleParallelParser!(ParserWrapper) singleParser = new SingleParallelParser!(ParserWrapper)(
            context);
    singleParser.startParse(context.isCPlusPlus, null, &globalStringPool);

    ParallelParser!(ParserWrapper) parser = singleParser;

    foreach (i, alwaysIncludeFile; context.fileCache.alwaysIncludeFiles)
    {
        auto mainLocContext = context.getLocationContext(immutable(LocationContext)(null,
                LocationN(), LocationN.LocationDiff(), "", inputFile.name));
        auto secondLocContext = context.getLocationContext(immutable(LocationContext)(mainLocContext,
                LocationN(), LocationN.LocationDiff(), "", "@@@"));
        processFile(alwaysIncludeFile, context, context.logicSystem.true_, parser,
                context.getLocationContext(immutable(LocationContext)(secondLocContext,
                    LocationN(cast(uint) i, cast(uint) i, 0),
                    LocationN.LocationDiff(), "", alwaysIncludeFile.name)));
    }

    foreach (n, d; context.defineSets.defineSets)
    {
        d.beforeMainFile = true;
    }

    immutable(Formula)* initialCondition = context.logicSystem.true_;
    foreach (tree; initialConditions)
    {
        immutable(LocationContext)* locationContextCmdline = context.getLocationContext(
                immutable(LocationContext)(null,
                LocationN(), LocationN.LocationDiff(), "", "@cmdline"));
        initialCondition = exprToCondition!(ParserWrapper)(tree.childs[1], locationContextCmdline,
                context.logicSystem.true_, context.logicSystem, context.defineSets);
    }

    if (initialCondition.isTrue)
    {
        processFile(inputFile, context, initialCondition, parser,
                context.getLocationContext(immutable(LocationContext)(null,
                    LocationN(), LocationN.LocationDiff(), "", inputFile.name)));
    }
    else
    {
        ParallelParser!(ParserWrapper) parser1 = parser;
        ParallelParser!(ParserWrapper) parser2 = parser.forkLazy();
        processFile(inputFile, context, initialCondition, parser1,
                context.getLocationContext(immutable(LocationContext)(null,
                    LocationN(), LocationN.LocationDiff(), "", inputFile.name)));

        parser = new DoubleParallelParser!ParserWrapper(context, [parser1, parser2], [initialCondition, initialCondition.negated]);
        parser1.removeReference(null);
        parser2.removeReference(null);
        tryMergeParser!(ParserWrapper)(parser, context.logicSystem.true_, context, null);
    }

    parser = parser.ensureUnique(null);
    parser.pushEnd(context.logicSystem.true_);

    parser = parser.tryMerge(context.logicSystem.true_, false, null);
    singleParser = parser.toSingleParser();

    context.checkReferences(true);

    assert(context.existingTopParsers.length == 1);
    assert(context.existingTopParsers[0].refCount == 1);

    {
        File outfile = File(generateExtraOutputPath(context, inputFile, "errors"), "w");
        foreach (reportedError; context.reportedErrors)
        {
            outfile.writeln(reportedError.condition.toString);
            outfile.writeln("\t", locationStr(reportedError.location));
            outfile.writeln("\t", reportedError.message);

            if (reportedError.condition.isTrue)
            {
                stderr.writeln(reportedError.location.context ? reportedError.location.context.filename : "", ":",
                    locationStr(reportedError.location.loc), ": ", reportedError.message);
            }
        }
    }

    assert(singleParser !is null);
    parser = singleParser;

    Tree pt;
    if (singleParser.errorNodes.length == 0)
        pt = singleParser.pushParser.getAcceptedTranslationUnit();

    // prevent subtrees with same references
    // they would cause problems in the semantic analysis
    pt = deepCopyTree(pt, context.logicSystem);

    {
        import std.datetime.stopwatch;

        auto sw = StopWatch(AutoStart.no);
        sw.start();
        normalizeLocations(pt, context.locationContextMap);
        buildLocations(context, context.locationContextInfoMap, pt, initialCondition);
        sw.stop();
        writeln("buildLocations ", sw.peek.total!"msecs", " ms");
    }

    context.parsedTree = pt;
}

void normalizeLocations(Tree pt, LocationContextMap locationContextMap)
{
    LocationRangeX lastLocation;
    LocationRangeX visitTree(Tree tree)
    {
        if (!tree.isValid)
            return LocationRangeX(LocationX.invalid);

        LocationRangeX lastLocationBak = lastLocation;

        bool endsWithSemicolon = tree.childs.length && tree.childs[$ - 1].isValid && tree.childs[$ - 1].isToken && tree.childs[$ - 1].content == ";";

        LocationRangeX commonLocation;
        size_t numLocations;
        foreach (i, c; tree.childs)
        {
            if (!c.isValid)
                continue;

            LocationRangeX location;
            if (c.nodeType == NodeType.token)
            {
                if (c.start.context !is null && !c.start.context.isPreprocLocation)
                {
                    location = c.location;
                }
            }
            else
            {
                location = visitTree(c);
            }
            if (location.context is null)
                continue;

            numLocations++;

            if (commonLocation.context is null)
            {
                commonLocation = location;
                continue;
            }

            if (endsWithSemicolon && i == tree.childs.length - 1)
            {
                LocationRangeX a = commonLocation;
                findCommonLocationContext(a, location);
                a = commonLocation;
                findCommonLocationContext(a, lastLocationBak);
                if (location.context is c.location.context && location.context !is commonLocation.context
                    && (numLocations > 2 || lastLocationBak.contextDepth > location.contextDepth))
                {
                    auto newContext = locationContextMap.getLocationContext(
                        immutable(LocationContext)(commonLocation.context, commonLocation.start_ + commonLocation.inputLength_, LocationN.LocationDiff.init, "@semicolon",
                        c.location.context.filename, c.location.context.isPreprocLocation));

                    c.setStartEnd(LocationX(c.start.loc, newContext), LocationX(c.end.loc, newContext));
                    continue;
                }
            }

            findCommonLocationContext(commonLocation, location);
            LocationX start = minLoc(commonLocation.start, location.start);
            LocationX end = maxLoc(commonLocation.end, location.end);
            commonLocation.setStartEnd(start, end);
        }

        if (commonLocation.context is null)
            return LocationRangeX(LocationX.invalid);

        tree.setStartEnd(commonLocation.start, commonLocation.end);
        lastLocation = commonLocation;
        return commonLocation;
    }

    visitTree(pt);
}

void buildLocations(Context context, ref LocationContextInfoMap locationContextInfoMap,
        Tree pt, immutable(Formula)* contextCondition, Semantic semantic = null)
{
    locationContextInfoMap.getLocationContextInfo(null);

    void visitTree(Tree tree, size_t indent, bool topLevel, immutable(Formula)* condition)
    {
        if (!tree.isValid)
            return;

        bool topLevel2 = topLevel;
        if (tree.nodeType == NodeType.nonterminal && !(tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TranslationUnit"))
            topLevel2 = false;

        if (tree.start.context is null)
            return;

        LocationRangeX contextAbove(immutable(LocationContext)* lower, LocationRangeX upper)
        {
            assert(upper.contextDepth >= lower.contextDepth);
            while (upper.contextDepth > lower.contextDepth + 1)
                upper = upper.context.parentLocation;
            return upper;
        }

        void handleChilds(immutable(LocationContext)* locationContext,
                Tree[] childs, size_t indent, immutable(Formula)* condition)
        {
            /*while (childs.length && (childs[0] is null || childs[0].start.context is null))
                childs = childs[1..$];
            while (childs.length && (childs[$ - 1] is null || childs[$ - 1].start.context is null))
                childs = childs[0..$-1];
            if (childs.length == 0)
                return;*/

            LocationContextInfo locationContextInfo = locationContextInfoMap.getLocationContextInfo(
                    locationContext);
            size_t start;
            LocationRangeX currentRange;
            bool sameContextAsPrev;
            void onEnd(size_t end, bool insideConcat = false)
            {
                if (currentRange.context is null)
                    return;

                while (start < end && (!childs[start].isValid || childs[start].start.context is null))
                    start++;
                while (start < end && (!childs[end - 1].isValid
                        || childs[end - 1].start.context is null))
                    end--;

                if (!insideConcat && currentRange.context.name == "##"
                        && currentRange.context.filename == "@concat")
                {
                    assert(currentRange.context.prev.name == "##");
                    Tree sourceTokens = locationContextInfoMap.getLocationContextInfo(currentRange.context.prev)
                        .sourceTokens;
                    assert(sourceTokens.name == "ParamConcat" && sourceTokens.childs.length == 1);
                    bool started;
                    foreach (i, x; sourceTokens.childs[0].childs)
                    {
                        if (i % 2 == 0)
                            continue;
                        assert(x.name == "##");
                        //assert(x.start.context is currentRange.context.prev);
                        assert(x.start.context.filename == currentRange.context.prev.filename);
                        if (x.start.loc >= currentRange.context.startInPrev
                                && x.end.loc >= currentRange.context.startInPrev
                                + currentRange.context.lengthInPrev)
                        {
                            if (!started)
                            {
                                immutable(LocationContext)* locationContext2 = sourceTokens.childs[0].childs[i
                                    - 1].childs[0].start.context;
                                LocationContextInfo locationContextInfo2 = locationContextInfoMap
                                    .getLocationContextInfo(locationContext2);

                                if (locationContextInfo2.trees.entries.length
                                        && !context.logicSystem.and(locationContextInfo2.trees.conditionAll,
                                            condition).isFalse)
                                {
                                    locationContextInfo2.warnings
                                        ~= "WARNING: location context at multiple trees";
                                }
                                locationContextInfo2.trees.addNew(condition,
                                        childs[start .. end], context.logicSystem);

                                onEnd(end, true);
                            }
                            {
                                immutable(LocationContext)* locationContext2 = sourceTokens.childs[0].childs[i
                                    + 1].childs[0].start.context;
                                LocationContextInfo locationContextInfo2 = locationContextInfoMap
                                    .getLocationContextInfo(locationContext2);

                                if (locationContextInfo2.trees.entries.length
                                        && !context.logicSystem.and(locationContextInfo2.trees.conditionAll,
                                            condition).isFalse)
                                {
                                    locationContextInfo2.warnings
                                        ~= "WARNING: location context at multiple trees";
                                }
                                locationContextInfo2.trees.addNew(condition,
                                        childs[start .. end], context.logicSystem);
                            }
                            started = true;
                        }
                    }
                    return;
                }

                LocationContextInfo locationContextInfo2 = locationContextInfoMap.getLocationContextInfo(
                        currentRange.context);

                if (currentRange.context.name.length == 0 && !topLevel2)
                    context.getFileInstanceInfo(RealFilename(currentRange.context.filename))
                        .badInclude = true;

                if (!sameContextAsPrev && locationContextInfo2.trees.entries.length
                        && !context.logicSystem.and(locationContextInfo2.trees.conditionAll,
                            condition).isFalse)
                {
                    locationContextInfo2.warnings ~= "WARNING: location context at multiple trees";
                    locationContextInfo2.badInclude = true;
                    if (!currentRange.context.name.length)
                        context.getFileInstanceInfo(RealFilename(currentRange.context.filename))
                            .badInclude = true;
                }

                if (childs[start .. end].length)
                    locationContextInfo2.trees.addNew(condition,
                            childs[start .. end], context.logicSystem);

                handleChilds(currentRange.context, childs[start .. end], indent + 2, condition);
                currentRange = LocationRangeX.invalid;
                sameContextAsPrev = false;
            }

            foreach (i, c; childs)
            {
                if (!c.isValid || c.start.context is null)
                    continue;

                auto nextContext = contextAbove(locationContext, c.location);
                if (nextContext.context is locationContext)
                {
                    onEnd(i);
                    visitTree(c, indent + 2, topLevel2, condition);
                }
                else if (nextContext.context !is currentRange.context
                        || tree.nodeType != NodeType.array)
                {
                    bool bad = nextContext.context is currentRange.context;

                    onEnd(i);

                    if (bad)
                    {
                        LocationContextInfo locationContextInfo2 = locationContextInfoMap.getLocationContextInfo(
                                nextContext.context);
                        locationContextInfo2.warnings
                            ~= "WARNING: same location context as previous";
                        sameContextAsPrev = true;
                        locationContextInfo2.badInclude = true;
                        if (!nextContext.context.name.length)
                            context.getFileInstanceInfo(RealFilename(nextContext.context.filename))
                                .badInclude = true;
                    }

                    start = i;
                    currentRange = nextContext;
                }
                else
                {
                    currentRange.setStartEnd(currentRange.start, nextContext.end);
                }
            }
            onEnd(childs.length);
        }

        if (semantic !is null && tree.nodeType == NodeType.merged
                && tree in semantic.mergedTreeDatas)
        {
            auto mergedTreeData = semantic.mergedTreeDatas[tree];
            if (mergedTreeData.mergedCondition !is null && mergedTreeData.mergedCondition.isFalse)
            {
                foreach (i, c; mergedTreeData.conditions)
                {
                    if (!c.isFalse)
                    {
                        handleChilds(tree.start.context, tree.childs[i .. i + 1],
                                indent, context.logicSystem.and(condition, c));
                    }
                }
                return;
            }
        }
        if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            auto ctree = tree.toConditionTree;

            foreach (i, c; ctree.conditions)
            {
                if (!c.isFalse)
                {
                    handleChilds(tree.start.context, tree.childs[i .. i + 1],
                            indent, context.logicSystem.and(condition, c));
                }
            }
            return;
        }
        handleChilds(tree.start.context, tree.childs, indent, condition);
    }

    if (pt.isValid)
    {
        for (auto l = pt.start; l.context !is null; l = l.context.parentLocation.start)
        {
            LocationContextInfo locationContextInfo = locationContextInfoMap.getLocationContextInfo(
                    l.context);
            if (pt.nodeType == NodeType.nonterminal
                    && pt.nonterminalID == nonterminalIDFor!"TranslationUnit")
                locationContextInfo.trees.addNew(context.logicSystem.true_,
                        pt.childs[0].childs, context.logicSystem);
            else if (pt.nodeType == NodeType.nonterminal
                    && pt.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                auto ctree = pt.toConditionTree;
                Tree[] newChilds;
                foreach (i; 0 .. ctree.childs.length)
                {
                    assert(ctree.childs[i].nodeType == NodeType.nonterminal
                            && ctree.childs[i].nonterminalID == nonterminalIDFor!"TranslationUnit");
                    newChilds ~= ctree.childs[i].childs[0];
                }

                locationContextInfo.trees.addNew(context.logicSystem.true_,
                        [createConditionTree(newChilds, ctree.conditions).toTree], context.logicSystem);
            }
            else
                locationContextInfo.trees.addNew(context.logicSystem.true_,
                        [pt], context.logicSystem);
        }

        visitTree(pt, 0, true, context.logicSystem.true_);
    }
}
