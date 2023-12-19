
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppparallelparser;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.filecache;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.parallelparser;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.stringtable;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.parseexception;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.typecons;

alias Location = LocationX;

alias Tree = CppParseTree;
alias TreeArray = CppParseTreeArray;

struct ReportedError
{
    Location location;
    immutable(Formula)* condition;
    string message;
}

alias getDummyGrammarInfo2 = cppconv.parallelparser.getDummyGrammarInfo2;

class Context(ParserWrapper)
{
    LogicSystem logicSystem;
    this()
    {
        logicSystem = new LogicSystem();
        anyErrorCondition = logicSystem.false_;
    }

    this(LogicSystem logicSystem, DefineSets defineSets)
    {
        this.logicSystem = logicSystem;
        this.defineSets = defineSets;
        anyErrorCondition = logicSystem.false_;
    }

    DefineSets defineSets;
    DefineSets[RealFilename] defineSetsByFile;

    size_t[RealFilename] fileIncludeDepth;

    string extraOutputStr;
    bool isCPlusPlus;
    bool addLocationInstances;
    bool ignoreMissingIncludePath;

    FileCache fileCache;
    LocationContextInfoMap locationContextInfoMap;
    FileInstanceInfo[RealFilename] fileInstanceInfos;
    FileInstanceInfo getFileInstanceInfo(RealFilename filename)
    {
        auto x = filename in fileInstanceInfos;
        if (x)
            return *x;
        auto r = new FileInstanceInfo;
        fileInstanceInfos[filename] = r;
        return r;
    }

    size_t[immutable(LocationContext)*] locationUniqueNumbers;

    MacroInstanceInfo[immutable(LocationContext)*] macroInstanceInfos;

    ReportedError[] reportedErrors;
    immutable(Formula)* anyErrorCondition;
    bool insidePPExpression;

    SingleParallelParser!(ParserWrapper) singleParser;
    immutable(Formula)*[Tree] defineConditions;
    immutable(Formula)*[string] unknownConditions;
    immutable(Formula)*[string] undefConditions;
    Tree parsedTree;

    void addError(Location location, immutable(Formula)* condition, string message)
    {
        if (logicSystem.or(anyErrorCondition, condition) is anyErrorCondition)
            return;
        anyErrorCondition = logicSystem.or(anyErrorCondition, condition);
        reportedErrors ~= ReportedError(location, condition, message);
    }

    void addWarning(Location location, immutable(Formula)* condition, string message)
    {
        reportedErrors ~= ReportedError(location, condition, message);
    }

    LocationContextMap locationContextMap;
    immutable(LocationContext)* getLocationContext(immutable(LocationContext) c)
    {
        auto r = locationContextMap.getLocationContext(c);
        locationContextInfoMap.getLocationContextInfo(r);
        return r;
    }

    ParallelParser!(ParserWrapper)[] existingTopParsers;
    bool[ParallelParser!(ParserWrapper)] existingParsers;
    void addExistingTopParsers(ParallelParser!(ParserWrapper) p) // work around circular reference testcircular2
    {
        existingTopParsers ~= p;
        existingParsers[p] = true;
    }

    void dumpAllStates()
    {
        writeln("dump:");
        foreach (x; existingTopParsers)
            x.dumpStates("  ", logicSystem.false_, false);
    }

    void checkReferences(bool checkLost = false)
    {
        static size_t[ParallelParser!(ParserWrapper)] counter;
        scope (exit)
            counter.clear();
        foreach (x; existingTopParsers)
        {
            x.countReferences(counter);
        }
        bool correct = true;
        foreach (x, c; counter)
        {
            if (x.refCount != c)
                correct = false;
        }
        if (checkLost)
            foreach (p, _; existingParsers)
            {
                if (p !in counter)
                    correct = false;
            }
        if (correct)
            return;
        dumpAllStates();
        foreach (x, c; counter)
        {
            writeln("parser ", cast(void*) x, "  ", x.refCount, "  ", c);
        }
        foreach (p, _; existingParsers)
        {
            if (p !in counter)
                writeln("lost parser ", cast(void*) p);
        }
        assert(false);
    }
}

abstract class ParallelParser(ParserWrapper)
{
    Context!(ParserWrapper) context;
    size_t refCount = 1;
    ParallelParser!(ParserWrapper)[] referencingParsers;

    this(Context!(ParserWrapper) context)
    {
        this.context = context;
        referencingParsers ~= null;
        context.addExistingTopParsers(this);
    }

    abstract ParallelParser pushToken(Tree token, Location start, immutable(Formula)* condition,
            bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parentParser)
    in (refCount == 1);
    abstract void pushEnd(immutable(Formula)* condition)
    in (refCount == 1);

    abstract void terminateFuncMacros(immutable(Formula)* condition, bool[string] macrosDone);

    SingleParallelParser!(ParserWrapper) toSingleParser()
    {
        return null;
    }

    DoubleParallelParser!(ParserWrapper) toDoubleParser()
    {
        return null;
    }

    void addReference(ParallelParser!(ParserWrapper) p)
    {
        assert(refCount);
        assert(referencingParsers.length == refCount);
        if (p is null)
        {
            context.existingTopParsers ~= this;
        }
        referencingParsers ~= p;
        refCount++;
        assert(referencingParsers.length == refCount);
    }

    void removeReference(ParallelParser!(ParserWrapper) p)
    {
        assert(referencingParsers.length == refCount);
        refCount--;
        foreach (i; 0 .. referencingParsers.length)
        {
            if (referencingParsers[i] is p)
            {
                referencingParsers[i] = referencingParsers[$ - 1];
                referencingParsers.length--;
                break;
            }
        }
        assert(referencingParsers.length == refCount);
        if (p is null)
        {
            bool found = false;
            foreach (i; 0 .. context.existingTopParsers.length)
            {
                if (context.existingTopParsers[i] is this)
                {
                    context.existingTopParsers[i] = context.existingTopParsers[$ - 1];
                    context.existingTopParsers.length--;
                    found = true;
                    break;
                }
            }
            assert(found);
        }
        if (refCount == 0)
            removeSelfReferences();
        if (refCount == 0)
            context.existingParsers.remove(this);
    }

    abstract void removeSelfReferences();

    void moveReference(ParallelParser!(ParserWrapper) from, ParallelParser!(ParserWrapper) to)
    {
        addReference(to);
        removeReference(from);
    }

    abstract void countReferences(ref size_t[ParallelParser!(ParserWrapper)] counter);

    abstract ParallelParser!(ParserWrapper) fork();
    final ParallelParser!(ParserWrapper) forkLazy()
    {
        addReference(null);
        return this;
    }

    abstract ParallelParser!(ParserWrapper) tryMerge(immutable(Formula)* contextCondition,
            bool preserveParsers, ParallelParser!(ParserWrapper) parentParser);
    abstract ParallelParser!(ParserWrapper) filterParser(LogicSystem logicSystem,
            immutable(Formula)* condition, bool preserveParsers,
            ParallelParser!(ParserWrapper) parentParser);

    abstract void dumpStates(string indent,
            immutable(Formula*) contextCondition, bool includeGraph = false);
    bool droppedParser() const
    {
        return false;
    }

    ParallelParser!(ParserWrapper) ensureUnique(ParallelParser!(ParserWrapper) parent)
    {
        assert(refCount >= 1);
        if (refCount > 1)
        {
            auto n = fork();
            removeReference(parent);
            n.moveReference(null, parent);
            assert(n.refCount == 1);
            return n;
        }
        else
            return this;
    }
}

ParallelParser!(ParserWrapper) expandMacros(ParserWrapper)(
        Context!ParserWrapper context, Tree token, Location start, immutable(
        Formula)* condition, bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parallelParser,
        ParallelParser!(ParserWrapper) parentParser, bool argPrescan)
{
    if (context.defineSets.getDefineSetOrNull(token.content) is null
            || (token.content in macrosDone && macrosDone[token.content]))
    {
        if (argPrescan)
        {
            processDirectToken!(ParserWrapper)(start, token, context,
                    parallelParser, condition, macrosDone, isNextParen, parentParser);
        }
        else
            parallelParser.toSingleParser().pushTokenDirect(token, start, condition);
        return parallelParser;
    }

    Tree nameToken = token;
    auto ds = context.defineSets.defineSets[token.content];
    ds.used = true;
    struct Case
    {
        immutable(Formula)* condition;
        immutable(Formula)* conditionSimplified;
        Define define;
        Tree[] tokens;
        bool isFuncMacro;
        ParallelParser!(ParserWrapper) parallelParser;
    }

    Case[] cases;
    foreach (d; ds.defines)
    {
        immutable(Formula)* simplifiedCcondition = context.logicSystem.simplify(
                context.logicSystem.removeRedundant(context.logicSystem.and(d.condition,
                condition), condition));

        if (simplifiedCcondition is context.logicSystem.false_)
            continue;

        if (d.definition.nonterminalID == preprocNonterminalIDFor!"VarDefine")
        {
            cases ~= Case(d.condition, simplifiedCcondition, d, d.definition.childs[7].childs);
        }
        else if (d.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
        {
            if (isNextParen)
            {
                cases ~= Case(d.condition, simplifiedCcondition, d, [token], true);
            }
            else
            {
                cases ~= Case(d.condition, simplifiedCcondition, null, [token]);
            }
        }
        else
        {
            assert(false);
        }
    }

    immutable(Formula)* defaultCondition;
    immutable(Formula)* undefCondition;
    if (!context.insidePPExpression || token.content.startsWith("@#defined"))
    {
        defaultCondition = context.logicSystem.simplify(
                context.logicSystem.or(ds.conditionUndef, ds.conditionUnknown));
        undefCondition = context.logicSystem.false_;
    }
    else
    {
        defaultCondition = ds.conditionUnknown;
        undefCondition = ds.conditionUndef;
    }

    immutable Formula* defaultConditionSimplified = context.logicSystem.simplify(
            context.logicSystem.removeRedundant(context.logicSystem.and(defaultCondition,
            condition), condition));
    immutable Formula* undefConditionSimplified = context.logicSystem.simplify(
            context.logicSystem.removeRedundant(context.logicSystem.and(undefCondition,
            condition), condition));

    if (!undefConditionSimplified.isFalse)
    {
        Tree newToken = Tree("0", SymbolID.max, ProductionID.max, NodeType.token, []);
        auto locationContextX = context.getLocationContext(immutable(LocationContext)(token.start.context,
                token.start.loc, token.inputLength, token.content, "",
                token.start.context.isPreprocLocation));
        auto newStart = LocationX(token.start.loc, locationContextX);
        auto newEnd = LocationX(token.end.loc, locationContextX);
        newToken.setStartEnd(newStart, newEnd);
        cases ~= Case(undefCondition, undefConditionSimplified, null, [newToken]);
    }

    if (defaultConditionSimplified !is context.logicSystem.false_ || cases.length == 0)
    {
        cases ~= Case(defaultCondition, defaultConditionSimplified, null, [token]);
    }

    foreach (i, ref c; cases)
    {
        ParallelParser!(ParserWrapper) parallelParserHere;
        if (i + 1 < cases.length)
        {
            parallelParserHere = parallelParser.forkLazy();
            parallelParserHere.moveReference(null, parentParser);
        }
        else
            parallelParserHere = parallelParser;
        c.parallelParser = parallelParserHere;

        auto caseCondition = context.logicSystem.simplify(context.logicSystem.and(condition,
                c.condition));
        if (c.isFuncMacro)
        {
            auto p2 = new FuncMacroParallelParser!(ParserWrapper)(context);
            p2.next = c.parallelParser;
            c.parallelParser.moveReference(parentParser, p2);
            p2.nameToken = c.tokens[0];
            p2.define = c.define;
            p2.location = start;
            p2.argPrescan = argPrescan;
            c.parallelParser = p2;
            c.parallelParser.moveReference(null, parentParser);
        }
        else
        {
            if (c.define is null)
            {
                parallelParserHere = parallelParserHere.ensureUnique(parentParser);
                c.parallelParser = parallelParserHere;
                Location start2 = start;
                if (c.tokens[0] !is token)
                {
                    auto locationContextX = context.getLocationContext(immutable(LocationContext)(start.context,
                            start.loc, token.inputLength, token.content, "",
                            start.context.isPreprocLocation));
                    start2 = LocationX(token.start.loc, locationContextX);
                }

                if (argPrescan)
                {
                    parallelParserHere = parallelParserHere.ensureUnique(parentParser);
                    parallelParserHere = parallelParserHere.pushToken(c.tokens[0],
                            start2, caseCondition, macrosDone, isNextParen, parentParser);
                }
                else
                    parallelParserHere.toSingleParser()
                        .pushTokenDirect(c.tokens[0], start2, caseCondition);
            }
            else
            {
                auto l = c.define.definition.location;
                auto locationContextX = context.getLocationContext(immutable(LocationContext)(start.context,
                        start.loc, token.inputLength, nameToken.content, ""));

                auto locationContextX2 = context.getLocationContext(
                        immutable(LocationContext)(locationContextX, LocationN.init,
                        LocationN.LocationDiff.init, nameToken.content,
                        c.define.definition.start.context.filename));

                LocationX l2 = LocationX(c.define.definition.start.loc, locationContextX2);

                auto locationContextX3 = context.getLocationContext(immutable(LocationContext)(l2.context,
                        l2.loc, c.define.definition.inputLength, "^",
                        c.define.definition.start.context.filename));

                context.locationContextInfoMap.getLocationContextInfo(locationContextX3)
                    .condition = caseCondition;

                macrosDone[nameToken.content] = true;
                scope (exit)
                    macrosDone[nameToken.content] = false;

                processMacroContent(locationContextX3, parseMacroContent(c.tokens,
                        context.insidePPExpression), context,
                        caseCondition, c.parallelParser, null, macrosDone,
                        isNextParen, parentParser, argPrescan);
            }
        }
    }

    ParallelParser!(ParserWrapper) parallelParserResult;
    if (cases.length == 1)
    {
        parallelParserResult = cases[0].parallelParser; // Nothing changed
    }
    else
    {
        parallelParserResult = cases[$ - 1].parallelParser;
        parallelParserResult.addReference(null);
        parallelParserResult.removeReference(parentParser);
        immutable(Formula)* conditionElse = cases[$ - 1].condition;
        for (size_t i = cases.length - 1; i > 0; i--)
        {
            auto r = new DoubleParallelParser!(ParserWrapper)(context, cases[i - 1].parallelParser,
                    cases[i - 1].condition, parallelParserResult, conditionElse);
            cases[i - 1].parallelParser.removeReference(parentParser);
            parallelParserResult.removeReference(null);
            conditionElse = context.logicSystem.or(conditionElse, cases[i - 1].condition);
            parallelParserResult = r;
        }
        parallelParserResult.moveReference(null, parentParser);
    }
    if (parentParser is null)
        context.checkReferences();
    return parallelParserResult;
}

class SingleParallelParser(ParserWrapper) : ParallelParser!(ParserWrapper)
{
    ParserWrapper pushParser;
    Tree[] errorNodes;
    bool isInitialParseState;
    Tree[] pragmaParseState;
    ubyte currentStructPacking;
    immutable(ubyte)[] structPackingStack;

    this(Context!(ParserWrapper) context)
    {
        super(context);
    }

    override void removeSelfReferences()
    {
    }

    override void countReferences(ref size_t[ParallelParser!(ParserWrapper)] counter)
    {
        if (this !in counter)
            counter[this] = 0;
        counter[this]++;
    }

    override void terminateFuncMacros(immutable(Formula)* condition, bool[string] macrosDone)
    {
    }

    override SingleParallelParser!(ParserWrapper) toSingleParser()
    {
        return this;
    }

    void startParse(bool isCPlusPlus, SimpleClassAllocator!(CppParseTreeStruct*) allocator,
            StringTable!(ubyte[0])* stringPool)
    {
        pushParser.isCPlusPlus = isCPlusPlus;
        pushParser.startParseTranslationUnit(allocator, stringPool);
        isInitialParseState = true;
    }

    void startParseExpr(bool isCPlusPlus, SimpleClassAllocator!(
            CppParseTreeStruct*) allocator, StringTable!(ubyte[0])* stringPool)
    {
        pushParser.isCPlusPlus = isCPlusPlus;
        pushParser.startParseExpression(allocator, stringPool);
        isInitialParseState = true;
    }

    void handlePragma(string content, immutable(Formula)* condition)
    {
        // https://gcc.gnu.org/onlinedocs/gcc-4.4.4/gcc/Structure_002dPacking-Pragmas.html
        string[] toks = ParserWrapper.splitTokens(content);

        if (toks.length && toks[0] == "pack")
        {
            enforce(toks.length >= 3);
            enforce(toks[1] == "(");
            enforce(toks[$ - 1] == ")");
            toks = toks[2 .. $ - 1];
            if (toks.length == 0)
            {
                currentStructPacking = 0;
            }
            else if (toks[0] == "push")
            {
                structPackingStack ~= currentStructPacking;
                if (toks.length > 1)
                {
                    enforce(toks.length == 3);
                    enforce(toks[1] == ",");
                    immutable(LocationContext)* locationContext = context.getLocationContext(
                            immutable(LocationContext)(null,
                            LocationN.init, LocationN.LocationDiff.init, "", ""));
                    Tree valueTree = parsePPExpr!ParserWrapper(toks[2], locationContext,
                            condition, context.logicSystem, context.defineSets);
                    assert(valueTree.nonterminalID == nonterminalIDFor!"Literal");
                    currentStructPacking = valueTree.childs[0].content.to!ubyte;
                }
            }
            else if (toks[0] == "pop")
            {
                currentStructPacking = structPackingStack[$ - 1];
                structPackingStack = structPackingStack[0 .. $ - 1];
            }
            else
            {
                immutable(LocationContext)* locationContext = context.getLocationContext(
                        immutable(LocationContext)(null,
                        LocationN.init, LocationN.LocationDiff.init, "", ""));
                Tree valueTree = parsePPExpr!ParserWrapper(toks[0], locationContext,
                        condition, context.logicSystem, context.defineSets);
                assert(valueTree.nonterminalID == nonterminalIDFor!"Literal");
                currentStructPacking = valueTree.childs[0].content.to!ubyte;
            }
        }
    }

    void pushTokenDirect(Tree token, Location start, immutable(Formula)* condition)
    {
        assert(refCount == 1);
        isInitialParseState = false;

        if (token.content == "_Pragma" || pragmaParseState.length)
        {
            // https://gcc.gnu.org/onlinedocs/cpp/Pragmas.html
            if (pragmaParseState.length == 1 && token.content != "(")
            {
                errorNodes ~= Tree("#error parsing _Pragma", SymbolID.max,
                        ProductionID.max, NodeType.token, []);
                context.addError(start, condition, "#error parsing _Pragma");
                return;
            }
            if (pragmaParseState.length > 1 && token.content == ")")
            {
                string content;
                foreach (t; pragmaParseState[2 .. $])
                {
                    enforce(t.content.startsWith("\""));
                    string s = t.content[1 .. $ - 1];
                    for (size_t i; i < s.length; i++)
                    {
                        if (s[i] == '\\')
                        {
                            if (i + 1 < s.length && s[i + 1].among('\\', '"'))
                                i++;
                        }
                        content ~= s[i];
                    }
                }

                handlePragma(content, condition);

                pragmaParseState = [];
                return;
            }
            pragmaParseState ~= token;

            return;
        }

        try
        {
            pushParser.pushToken(token.content, start);
        }
        catch (ParseException e)
        {
            errorNodes ~= Tree("#error " ~ e.msg, SymbolID.max,
                    ProductionID.max, NodeType.token, []);

            context.addError(start, condition, e.msg);

            //dumpStates("  ", true);
            return;
        }

        if (currentStructPacking && (token.content.among("struct", "union")
                || (context.isCPlusPlus && token.content == "class")))
        {
            Location loc = start + token.inputLength;

            auto locationContextX = context.getLocationContext(immutable(LocationContext)(loc.context, loc.loc,
                    Location.LocationDiff.init, "#", "", loc.context.isPreprocLocation));
            loc = Location(LocationN.init, locationContextX);
            void w(string str)
            {
                pushParser.pushToken(str, loc);
                loc = loc + Location.LocationDiff.fromStr(str);
                loc = loc + Location.LocationDiff.fromStr(" ");
            }

            try
            {
                w("__attribute__");
                w("(");
                w("(");
                w("pragma_pack");
                w("(");
                w(text(currentStructPacking));
                w(")");
                w(")");
                w(")");
            }
            catch (ParseException e)
            {
                errorNodes ~= Tree("#error " ~ e.msg, SymbolID.max,
                        ProductionID.max, NodeType.token, []);

                context.addError(start, condition, e.msg);

                //dumpStates("  ", true);
                return;
            }
        }
    }

    override ParallelParser!(ParserWrapper) pushToken(Tree token, Location start, immutable(Formula)* condition,
            bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parentParser)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        if (errorNodes.length > 0)
            return this;

        if (context.insidePPExpression && token.content[0].inCharSet!"a-zA-Z_")
        {
            context.defineSets.getDefineSet(token.content);
        }

        return expandMacros(context, token, start, condition, macrosDone,
                isNextParen, this, parentParser, false);
    }

    override void pushEnd(immutable(Formula)* condition)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        if (errorNodes.length > 0)
            return;
        isInitialParseState = false;

        try
        {
            pushParser.pushEnd();
        }
        catch (ParseException e)
        {
            errorNodes ~= Tree("#error " ~ e.msg, SymbolID.max,
                    ProductionID.max, NodeType.token, []);

            context.addError(Location.init, condition, e.msg);
        }

        pragmaParseState = [];
        currentStructPacking = 0;
        structPackingStack = [];
    }

    override SingleParallelParser!(ParserWrapper) fork()
    {
        auto r = new SingleParallelParser(context);
        r.pushParser = pushParser;

        r.pushParser.pushParser.stackTops = r.pushParser.pushParser.stackTops.dup;
        r.pushParser.pushParser.acceptedStackTops = r.pushParser.pushParser.acceptedStackTops.dup;
        r.errorNodes = errorNodes;
        r.isInitialParseState = isInitialParseState;
        r.pragmaParseState = pragmaParseState;
        r.currentStructPacking = currentStructPacking;
        r.structPackingStack = structPackingStack;

        return r;
    }

    override ParallelParser!(ParserWrapper) tryMerge(immutable(Formula)* contextCondition,
            bool preserveParsers, ParallelParser!(ParserWrapper) parentParser)
    {
        return this;
    }

    override ParallelParser!(ParserWrapper) filterParser(LogicSystem logicSystem,
            immutable(Formula)* condition, bool preserveParsers,
            ParallelParser!(ParserWrapper) parentParser)
    {
        return this;
    }

    override void dumpStates(string indent, immutable(Formula*) contextCondition, bool includeGraph)
    {
        writeln(indent, "SingleParallelParser ", cast(void*) this, "  refCount ", refCount);
        foreach (errorNode; errorNodes)
        {
            writeln(indent, "error: ", errorNode.content);
        }
        if (includeGraph)
        {
            pushParser.dumpStates(context.logicSystem, indent);
        }
    }
}

class DoubleParallelParser(ParserWrapper) : ParallelParser!(ParserWrapper)
{
    ParallelParser!(ParserWrapper)[] childs;
    immutable(Formula)*[] childConditions;
    bool hasMerged;

    alias PushParser = typeof(SingleParallelParser!(ParserWrapper).init.pushParser);

    override void removeSelfReferences()
    {
        foreach (i; 0 .. childs.length)
        {
            childs[i].removeReference(this);
        }
    }

    override void countReferences(ref size_t[ParallelParser!(ParserWrapper)] counter)
    {
        if (this !in counter)
        {
            counter[this] = 0;
            foreach (i; 0 .. childs.length)
            {
                childs[i].countReferences(counter);
            }
        }
        counter[this]++;
    }

    override void terminateFuncMacros(immutable(Formula)* condition, bool[string] macrosDone)
    {
        foreach (i; 0 .. childs.length)
        {
            childs[i].terminateFuncMacros(condition, macrosDone);
        }
    }

    override bool droppedParser() const
    {
        if (!hasMerged)
        {
            foreach (i; 0 .. childs.length)
            {
                assert(!childs[i].droppedParser);
            }
        }
        return hasMerged;
    }

    override DoubleParallelParser!(ParserWrapper) toDoubleParser()
    {
        return this;
    }

    this(Context!(ParserWrapper) context)
    {
        super(context);
    }

    this(Context!(ParserWrapper) context, ParallelParser!(ParserWrapper) a,
            immutable(Formula)* conditionA, ParallelParser!(ParserWrapper) b,
            immutable(Formula)* conditionB)
    in
    {
        assert(!a.droppedParser);
        assert(!b.droppedParser);
    }
    do
    {
        super(context);
        a.addReference(this);
        b.addReference(this);
        childs = [a, b];
        childConditions = [conditionA, conditionB];
    }

    this(Context!(ParserWrapper) context,
            ParallelParser!(ParserWrapper)[] childs, immutable(Formula)*[] conditions)
    in
    {
        assert(childs.length == conditions.length);
        foreach (ref x; childs)
            assert(!x.droppedParser);
    }
    do
    {
        super(context);
        foreach (ref x; childs)
            x.addReference(this);
        this.childs = childs;
        this.childConditions = conditions;
    }

    final void ensureUniqueChilds()
    {
        foreach (i; 0 .. childs.length)
        {
            childs[i] = childs[i].ensureUnique(this);
        }
    }

    override ParallelParser!(ParserWrapper) pushToken(Tree token, Location start, immutable(Formula)* condition,
            bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parentParser)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        assert(!droppedParser);
        ensureUniqueChilds();
        foreach (i; 0 .. childs.length)
        {
            childs[i] = childs[i].pushToken(token, start,
                    context.logicSystem.simplify(context.logicSystem.and(childConditions[i],
                        condition)), macrosDone, isNextParen, this);
        }
        return this;
    }

    override void pushEnd(immutable(Formula)* condition)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        assert(!droppedParser);
        ensureUniqueChilds();
        foreach (i; 0 .. childs.length)
        {
            childs[i].pushEnd(context.logicSystem.simplify(context.logicSystem.and(childConditions[i],
                    condition)));
        }
    }

    override ParallelParser!(ParserWrapper) fork()
    {
        assert(!droppedParser);
        auto r = new DoubleParallelParser!(ParserWrapper)(context);
        r.childs.length = childs.length;
        r.childConditions.length = childConditions.length;
        foreach (i; 0 .. childs.length)
        {
            r.childs[i] = childs[i].fork();
            r.childConditions[i] = childConditions[i];
            r.childs[i].moveReference(null, r);
        }
        return r;
    }

    static bool canMerge(SingleParallelParser!(ParserWrapper)[2] childs2)
    {
        if (childs2[0].errorNodes.length > 0 || childs2[1].errorNodes.length > 0)
        {
            return true;
        }

        if (childs2[0].pragmaParseState.length || childs2[1].pragmaParseState.length)
            return false;
        if (childs2[0].currentStructPacking != childs2[1].currentStructPacking)
            return false;
        if (childs2[0].structPackingStack != childs2[1].structPackingStack)
            return false;

        return ParserWrapper.canMerge(childs2[0].pushParser, childs2[1].pushParser);
    }

    static SingleParallelParser!(ParserWrapper) doMerge(SingleParallelParser!(ParserWrapper)[2] childs2,
            immutable(Formula)*[2] childConditions2, Context!(ParserWrapper) context,
            immutable(Formula)* contextCondition,
            bool preserveParsers, ParallelParser!(ParserWrapper) parentParser)
    {
        SingleParallelParser!(ParserWrapper) r;
        bool hasError;
        if (childs2[0].errorNodes.length > 0 && childs2[1].errorNodes.length > 0)
        {
            childs2[0].errorNodes ~= childs2[1].errorNodes;
            r = childs2[0];
            hasError = true;
        }
        else if (childs2[0].errorNodes.length > 0)
        {
            r = childs2[1];
            hasError = true;
        }
        else if (childs2[1].errorNodes.length > 0)
        {
            r = childs2[0];
            hasError = true;
        }
        else
            r = childs2[0];
        if (hasError)
        {
            r.addReference(null);
            return r;
        }

        if (preserveParsers || r.refCount > 1)
            r = r.fork;
        else
            r.addReference(null);

        ParserWrapper.doMerge(childs2[0].pushParser, childs2[1].pushParser, r.pushParser,
                childConditions2, context.logicSystem,
                context.anyErrorCondition, contextCondition);

        return r;
    }

    override ParallelParser!(ParserWrapper) tryMerge(immutable(Formula)* contextCondition,
            bool preserveParsers, ParallelParser!(ParserWrapper) parentParser)
    in
    {
        assert(!droppedParser);
    }
    out (r)
    {
        if (r is this)
            assert(!droppedParser);
    }
    do
    {
        ParallelParser!(ParserWrapper)[] childParsers2;
        immutable(Formula)*[] childConditions2;
        ParallelParser!(ParserWrapper) errorParser;
        void addChilds(ParallelParser!(ParserWrapper) p, immutable(Formula)* condition,
                ParallelParser!(ParserWrapper) parentParser, bool preserveParsers)
        {
            auto doubleParser = cast(DoubleParallelParser) p;
            bool nextPreserveParsers = preserveParsers || refCount > 1;
            if (doubleParser !is null)
            {
                foreach (i; 0 .. doubleParser.childs.length)
                {
                    addChilds(doubleParser.childs[i], context.logicSystem.and(condition,
                            doubleParser.childConditions[i]), p, nextPreserveParsers);
                }
                return;
            }
            p.addReference(null);

            auto singleParser = p.toSingleParser;
            if (singleParser !is null && singleParser.errorNodes.length > 0)
            {
                if (errorParser !is null)
                    errorParser.removeReference(null);
                errorParser = singleParser;
                return;
            }

            foreach (i; 0 .. childParsers2.length)
            {
                if (childParsers2[i] is p)
                {
                    p.removeReference(null);
                    childConditions2[i] = context.logicSystem.or(childConditions2[i], condition);
                    return;
                }
            }
            p = p.tryMerge(context.logicSystem.and(contextCondition, condition), false, null);
            childParsers2 ~= p;
            childConditions2 ~= condition;
        }

        foreach (i; 0 .. childs.length)
            addChilds(childs[i], childConditions[i], this, false);
        removeReference(parentParser);

        if (childParsers2.length == 0)
        {
            if (refCount == 0)
            {
                hasMerged = true;
                childs = [];
            }

            errorParser.moveReference(null, parentParser);
            return errorParser;
        }
        else if (errorParser !is null)
            errorParser.removeReference(null);

        size_t outI;
        foreach (i; 0 .. childParsers2.length)
        {
            if (childParsers2[i] is null)
                continue;

            ParallelParser!(ParserWrapper) parser = childParsers2[i];
            immutable(Formula)* condition = childConditions2[i];
            childParsers2[i] = null;
            childConditions2[i] = null;

            SingleParallelParser!(ParserWrapper) singleParser = parser.toSingleParser();

            if (singleParser !is null)
            {
                foreach (k; i + 1 .. childParsers2.length)
                {
                    if (childParsers2[k] is null)
                        continue;

                    SingleParallelParser!(ParserWrapper) singleParser2 = childParsers2[k].toSingleParser();
                    if (singleParser2 is null)
                        continue;

                    if (canMerge([singleParser, singleParser2]))
                    {
                        singleParser = doMerge([singleParser, singleParser2], [
                            condition, childConditions2[k]
                        ], context, contextCondition, false, null);

                        condition = context.logicSystem.or(condition, childConditions2[k]);

                        parser.removeReference(null);
                        childParsers2[k].removeReference(null);
                        childParsers2[k] = null;
                        childConditions2[k] = null;
                        parser = singleParser;
                    }
                }
            }

            childParsers2[outI] = parser;
            childConditions2[outI] = condition;

            outI++;
        }
        childParsers2 = childParsers2[0 .. outI];
        childConditions2 = childConditions2[0 .. outI];

        if (childParsers2.length == 1)
        {
            childParsers2[0].moveReference(null, parentParser);
            return childParsers2[0];
        }
        auto r = new DoubleParallelParser!(ParserWrapper)(context);
        r.childs = childParsers2;
        r.childConditions = childConditions2;
        foreach (c; r.childs)
            c.moveReference(null, r);

        r.moveReference(null, parentParser);

        if (refCount == 0)
        {
            hasMerged = true;
            childs = [];
        }

        return r;
    }

    override ParallelParser!(ParserWrapper) filterParser(LogicSystem logicSystem,
            immutable(Formula)* condition, bool preserveParsers,
            ParallelParser!(ParserWrapper) parentParser)
    {
        bool nextPreserveParsers = preserveParsers || refCount > 1;
        ParallelParser!(ParserWrapper)[] newChilds;
        newChilds.length = childs.length;
        bool anyChildChanged = false;
        foreach (i; 0 .. childs.length)
        {
            newChilds[i] = childs[i].filterParser(logicSystem, condition,
                    nextPreserveParsers, this);
            if (newChilds[i]!is childs[i])
                anyChildChanged = true;
        }

        with (logicSystem)
        {
            bool allowFilter = true;

            bool anyImpossible = false;
            bool allImpossible = true;
            foreach (i; 0 .. childs.length)
            {
                if (simplify(and(childConditions[i], condition)) is false_)
                    anyImpossible = true;
                else
                    allImpossible = false;
            }

            if (allImpossible)
                allowFilter = false;

            if (!anyChildChanged && (!allowFilter || !anyImpossible))
                return this;

            DoubleParallelParser!(ParserWrapper) r;

            if (!preserveParsers && refCount == 1)
            {
                r = this;
                r.childs = newChilds;
            }
            else
            {
                r = new DoubleParallelParser!(ParserWrapper)(context);
                r.moveReference(null, parentParser);
                removeReference(parentParser);
                r.childs = newChilds;
                foreach (i; 0 .. childs.length)
                {
                    r.childs[i].addReference(r);
                }
            }

            if (allowFilter && anyImpossible)
            {
                ParallelParser!(ParserWrapper)[] childParsers2;
                immutable(Formula)*[] childConditions2;
                foreach (i; 0 .. childs.length)
                {
                    if (simplify(and(childConditions[i], condition)) is false_)
                    {
                        newChilds[i].removeReference(r);
                    }
                    else
                    {
                        childParsers2 ~= newChilds[i];
                        childConditions2 ~= childConditions[i];
                    }
                }
                r.childs = childParsers2;
                r.childConditions = childConditions2;
            }

            return r;
        }
    }

    override void dumpStates(string indent, immutable(Formula*) contextCondition, bool includeGraph)
    {
        writeln(indent, "DoubleParallelParser ", cast(void*) this, " refCount ", refCount);

        foreach (i; 0 .. childs.length)
        {
            writeln(indent, "  ", childConditions[i].toString);
            if (childs[i] is null)
                writeln(indent, "  ", "null parser");
            else
                childs[i].dumpStates(indent ~ "  ", context.logicSystem.and(contextCondition,
                        childConditions[i]), includeGraph);
        }
    }
}

Tree[] parseMacroContent(Tree[] defTokens, bool insidePPExpression)
{
    Tree[] r;

    defTokens = defTokens.dup;

    for (size_t i = 0; i < defTokens.length;)
    {
        if (insidePPExpression && defTokens[i].childs[0].isToken
                && defTokens[i].childs[0].content == "defined")
        {
            size_t end = i + 1;
            size_t nesting;
            string newText = "@#defined";
            while (end < defTokens.length && defTokens[end].isValid)
            {
                newText ~= defTokens[end].childs[0].content;
                if (defTokens[end].childs[0].content == "(")
                {
                    nesting++;
                }
                else if (defTokens[end].childs[0].content == ")")
                {
                    if (nesting == 0)
                        break;
                    nesting--;
                    if (nesting == 0)
                    {
                        end++;
                        break;
                    }
                }
                else if (nesting == 0)
                {
                    end++;
                    break;
                }
                end++;
            }
            Location.LocationDiff l = defTokens[end - 1].end - defTokens[i].start;
            Tree x = Tree(newText, SymbolID.max, ProductionID.max, NodeType.token, []);
            x.setStartEnd(defTokens[i].start, defTokens[i].start + l);
            auto grammarInfo = getDummyGrammarInfo2("Token");
            Tree xw = Tree("Token", grammarInfo.startNonterminalID,
                    grammarInfo.startProductionID, NodeType.nonterminal, [x]);
            xw.grammarInfo = grammarInfo;
            xw.setStartEnd(defTokens[i].start, defTokens[i].start + l);
            r ~= xw;
            i = end;
        }
        else if (i + 2 < defTokens.length
                && defTokens[i + 1].name.startsWith("Token")
                && defTokens[i + 1].childs[0].content == "##")
        {
            auto grammarInfo = getDummyGrammarInfo2("ParamConcat");
            Tree x = Tree("ParamConcat", grammarInfo.startNonterminalID,
                    grammarInfo.startProductionID, NodeType.nonterminal, defTokens[i .. i + 3].dup);
            x.grammarInfo = grammarInfo;
            x.setStartEnd(defTokens[i].start,
                    defTokens[i].start + Location.LocationDiff.fromStr(""));
            defTokens[i + 2] = x;
            i += 2;
        }
        else
        {
            r ~= defTokens[i];
            i++;
        }
    }

    return r;
}

struct ParamToken
{
    Tree t;
    bool[string] macrosDone;
}

struct MacroParam
{
    Tree[] tokensBefore; // "," or "("
    ParamToken[] tokens;
    LocationX startLoc, endLoc;
}

bool matchMacroParams(ParserWrapper)(Define define, MacroParam[] params, immutable(Formula)* condition,
        Context!(ParserWrapper) context, ref MacroParam[string] paramMap,
        ref Tree[] defTokens, bool argPrescan)
{
    size_t realParamsLength = params.length;
    if (params.length == 1 && params[$ - 1].tokens.length == 0)
        realParamsLength = 0;

    Tree[] defParams = define.definition.childs[7].childs;
    defTokens = define.definition.childs[10].childs;
    string[] paramNames;
    foreach (i, p; defParams)
    {
        if (i % 2 == 1) // ","
            continue;
        string pname;
        if (p.childs.length >= 2)
            pname = p.childs[1].content;
        paramNames ~= pname;
    }
    if (paramNames.length && paramNames[$ - 1] == "")
        paramNames.length--;

    bool isVariadic;
    if (paramNames.length && paramNames[$ - 1] == "...")
    {
        paramNames = paramNames[0 .. $ - 1];
        isVariadic = true;
    }

    foreach (i, p; params)
    {
        string pname;
        if (i < paramNames.length)
            pname = paramNames[i];
        else if (isVariadic)
            continue;
        else if (i < realParamsLength)
            pname = "parameter too much";
        else
            continue;
    }
    if (argPrescan && params.length < paramNames.length)
        return false;

    if (!isVariadic && realParamsLength > paramNames.length)
    {
        return false;
    }

    if (isVariadic)
    {
        paramNames ~= "__VA_ARGS__";
        MacroParam varParam;

        for (size_t i = paramNames.length - 1; i < params.length; i++)
        {
            if (i >= paramNames.length)
            {
                foreach (t; params[i].tokensBefore)
                    varParam.tokens ~= ParamToken(t);
            }
            varParam.tokens ~= params[i].tokens;
        }
        params.length = paramNames.length;
        params[$ - 1] = varParam;
    }

    paramMap = null;
    foreach (i, pname; paramNames)
    {
        MacroParam param;
        if (i < params.length)
            param = params[i];
        paramMap[pname] = param;
    }
    return true;
}

class FuncMacroParallelParser(ParserWrapper) : ParallelParser!(ParserWrapper)
{
    ParallelParser!(ParserWrapper) next;
    size_t numOpenedParens;
    bool paramsStarted;
    Tree nameToken;
    Define define;
    Location location;
    MacroParam[] params;
    bool[string] macrosDone;
    immutable(Formula)* firstCondition;
    bool argPrescan;

    this(Context!(ParserWrapper) context)
    {
        super(context);
    }

    override void removeSelfReferences()
    {
        next.removeReference(this);
    }

    override void countReferences(ref size_t[ParallelParser!(ParserWrapper)] counter)
    {
        if (this !in counter)
        {
            counter[this] = 0;
            next.countReferences(counter);
        }
        counter[this]++;
    }

    override void terminateFuncMacros(immutable(Formula)* condition, bool[string] macrosDone)
    {
        if (paramsStarted && numOpenedParens != 0)
        {
            numOpenedParens = 0;
            next = next.pushToken(nameToken, reparentLocation(nameToken.start,
                    location.context), condition, macrosDone, false, this);
        }
    }

    override ParallelParser!(ParserWrapper) pushToken(Tree token, Location start, immutable(Formula)* condition,
            bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parentParser)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        if (firstCondition is null)
            firstCondition = condition;

        auto savedInputLength = token.inputLength;
        token = Tree(token.content, SymbolID.max, ProductionID.max, NodeType.token, []);
        token.setStartEnd(start, start + savedInputLength);

        if (!paramsStarted)
        {
            assert(token.content == "(", token.content);
            numOpenedParens = 1;
            paramsStarted = true;

            this.macrosDone = macrosDone.dup;
            this.macrosDone[nameToken.content] = true;

            params ~= MacroParam([token], [], token.end);

            return this;
        }
        if (numOpenedParens == 0)
        {
            next = next.pushToken(token, start, condition, macrosDone, isNextParen, this);
            return this;
        }

        bool allowParenComma = true;
        if (argPrescan)
        {
            Location commonLoc1 = location;
            Location commonLoc2 = start;
            findCommonLocationContext(commonLoc1, commonLoc2);
            allowParenComma = start.context is commonLoc2.context;
        }
        if (token.content == "(" && allowParenComma)
            numOpenedParens++;
        else if (token.content == ")" && allowParenComma)
            numOpenedParens--;

        if (numOpenedParens == 1 && token.content == "," && allowParenComma)
        {
            params[$ - 1].endLoc = token.start;
            params ~= MacroParam([token], [], token.end);
        }
        else if (numOpenedParens > 0)
            params[$ - 1].tokens ~= ParamToken(token, macrosDone.dup);

        if (numOpenedParens == 0)
        {
            assert(token.content == ")");
            LocationN.LocationDiff funcMacroLength = nameToken.inputLength;
            if (location.context is start.context)
                funcMacroLength = start + token.inputLength - location;
            params[$ - 1].endLoc = token.start;
            finish(funcMacroLength, context.logicSystem.and(firstCondition,
                    condition), isNextParen);
        }
        return this;
    }

    override void pushEnd(immutable(Formula)* condition)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        if (numOpenedParens == 0)
        {
            next.pushEnd(condition);
            return;
        }
        assert(false, "TODO");
    }

    static void replaceFunctionMacro(Define define, MacroParam[] params, Tree nameToken, immutable(Formula)* condition,
            Location location, LocationN.LocationDiff funcMacroLength, Context!(ParserWrapper) context,
            ref ParallelParser!(ParserWrapper) next, bool[string] macrosDone,
            bool isNextParen, ParallelParser!(ParserWrapper) parentParser, bool argPrescan)
    {
        MacroParam[string] paramMap;
        Tree[] defTokens;
        if (!matchMacroParams(define, params, condition, context, paramMap, defTokens, argPrescan))
        {
            next = next.ensureUnique(parentParser);
            next = next.pushToken(nameToken, reparentLocation(nameToken.start,
                    location.context), condition, macrosDone, false, parentParser);
            return;
        }

        defTokens = parseMacroContent(defTokens, context.insidePPExpression);

        assert(location.context.name.among("", "^", "##"), locationStr(location));
        string name2 = nameToken.content;
        if (params.length && params[0].tokensBefore.length
                && location.context !is params[0].tokensBefore[0].start.context
                && location.context.prev !is null && location.context.prev.name.canFind("."))
        {
            name2 ~= "^" ~ location.context.prev.name.findSplit(".")[2];
        }

        auto l = define.definition.location;
        auto locationContextX = context.getLocationContext(immutable(LocationContext)(location.context,
                location.loc, funcMacroLength, name2, ""));

        auto locationContextX2 = context.getLocationContext(
                immutable(LocationContext)(locationContextX, LocationN.init,
                LocationN.LocationDiff.init, name2, define.definition.start.context.filename));

        LocationX l2 = LocationX(define.definition.start.loc, locationContextX2);

        auto locationContextX3 = context.getLocationContext(immutable(LocationContext)(l2.context, l2.loc,
                define.definition.inputLength, "^", define.definition.start.context.filename));

        context.locationContextInfoMap.getLocationContextInfo(locationContextX3)
            .condition = condition;

        processMacroContent(locationContextX3, defTokens, context, condition,
                next, paramMap, macrosDone, isNextParen, parentParser, argPrescan);
    }

    void finish(LocationN.LocationDiff funcMacroLength,
            immutable(Formula)* condition, bool isNextParen)
    {
        replaceFunctionMacro(define, params, nameToken, condition, location,
                funcMacroLength, context, next, macrosDone, isNextParen, this, argPrescan);
    }

    override ParallelParser!(ParserWrapper) fork()
    {
        auto r = new FuncMacroParallelParser(context);
        r.next = next.fork();
        r.next.moveReference(null, r);
        r.numOpenedParens = numOpenedParens;
        r.paramsStarted = paramsStarted;
        r.nameToken = nameToken;
        r.define = define;
        r.location = location;
        r.macrosDone = macrosDone;
        r.firstCondition = firstCondition;
        r.argPrescan = argPrescan;
        foreach (p; params)
            r.params ~= MacroParam(p.tokensBefore.dup, p.tokens.dup);
        return r;
    }

    override ParallelParser!(ParserWrapper) tryMerge(immutable(Formula)* contextCondition,
            bool preserveParsers, ParallelParser!(ParserWrapper) parentParser)
    {
        if (paramsStarted && numOpenedParens == 0)
        {
            next.addReference(parentParser);
            //next.removeReference(this);
            this.removeReference(parentParser);
            return next;
        }
        return this;
    }

    override ParallelParser!(ParserWrapper) filterParser(LogicSystem logicSystem,
            immutable(Formula)* condition, bool preserveParsers,
            ParallelParser!(ParserWrapper) parentParser)
    in
    {
        assert(refCount == 1);
    }
    do
    {
        bool nextPreserveParsers = preserveParsers || refCount > 1;
        ParallelParser!(ParserWrapper) newNext = next.filterParser(logicSystem,
                condition, nextPreserveParsers, this);
        if (newNext is next)
            return this;

        if (!nextPreserveParsers)
        {
            next = newNext;
            return this;
        }

        auto r = new FuncMacroParallelParser(context);
        r.next = newNext;
        r.numOpenedParens = numOpenedParens;
        r.paramsStarted = paramsStarted;
        r.nameToken = nameToken;
        r.define = define;
        r.location = location;
        r.macrosDone = macrosDone;
        foreach (p; params)
            r.params ~= MacroParam(p.tokensBefore.dup, p.tokens.dup);
        r.next = newNext;
        if (newNext is next) /* always false */
            newNext.refCount++;
        if (!preserveParsers)
            refCount--;
        return r;
    }

    override void dumpStates(string indent, immutable(Formula*) contextCondition, bool includeGraph)
    {
        writeln(indent, "FuncMacroParallelParser ", cast(void*) this, "  refCount ", refCount);
        next.dumpStates(indent ~ "  ", contextCondition, includeGraph);
    }
}

SingleParallelParser!(ParserWrapper) tryMergeParser(ParserWrapper)(
        ref ParallelParser!(ParserWrapper) parallelParser, immutable(
        Formula)* contextCondition, Context!(ParserWrapper) context,
        ParallelParser!(ParserWrapper) parentParser)
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
    //context.checkReferences();
    parallelParser = parallelParser.tryMerge(contextCondition, false, parentParser);
    stdout.flush();
    //context.checkReferences();
    auto x = parallelParser.toSingleParser();
    return x;
}

void processDirectToken(ParserWrapper)(Location start, Tree token, Context!(ParserWrapper) context,
        ref ParallelParser!(ParserWrapper) parallelParser, immutable(Formula)* condition,
        bool[string] macrosDone, bool isNextParen, ParallelParser!(ParserWrapper) parentParser)
in
{
    assert(!parallelParser.droppedParser);
    assert(token.nodeType == NodeType.token, text(token.nodeType, " ", token));
}
out
{
    assert(!parallelParser.droppedParser);
}
do
{
    if (parentParser is null)
        context.checkReferences();
    start = reparentLocation(token.start, start.context);

    {
        parallelParser = parallelParser.ensureUnique(parentParser);
        parallelParser = parallelParser.pushToken(token, start, condition,
                macrosDone, isNextParen, parentParser);
        if (parentParser is null)
            context.checkReferences();
        tryMergeParser(parallelParser, condition, context, parentParser);
        if (parentParser is null)
            context.checkReferences();
    }
}

void processMacroContent(ParserWrapper)(immutable(LocationContext)* locationContext,
        Tree[] tokens, Context!(ParserWrapper) context,
        immutable Formula* condition, ref ParallelParser!(ParserWrapper) parallelParser, MacroParam[string] paramMap,
        bool[string] macrosDone, bool isNextParen,
        ParallelParser!(ParserWrapper) parentParser, bool argPrescan)
{
    size_t maxEnd;
    foreach (i, t; tokens)
    {
        auto end = t.end;
        if (end.bytePos > maxEnd)
            maxEnd = end.bytePos;

        string filename = (t.start.context is null) ? "" : t.start.context.filename;
        assert(filename == locationContext.filename);
        LocationX location = LocationX(t.start.loc, locationContext);

        bool isNextParen2;
        if (i + 1 < tokens.length)
            isNextParen2 = tokens[i + 1].childs[0].isToken && tokens[i + 1].childs[0].content == "(";
        else
            isNextParen2 = isNextParen;
        processToken(location, t, context, condition, parallelParser,
                isNextParen2, paramMap, location, macrosDone, parentParser, argPrescan);
    }
}

Tuple!(Tree, Location)[] mapParams(ParserWrapper)(Location start, Tree nameToken, MacroParam[string] paramMap,
        Context!(ParserWrapper) context, Location funcMacroLocation, immutable(Formula)* condition)
{
    Tuple!(Tree, Location)[] r;
    foreach (i, t2; paramMap[nameToken.content].tokens)
    {
        LocationX commonLoc1 = t2.t.start;
        LocationX commonLoc2 = funcMacroLocation;
        findCommonLocationContext(commonLoc1, commonLoc2);

        auto startLoc = paramMap[nameToken.content].startLoc;
        auto endLoc = paramMap[nameToken.content].endLoc;
        bool goodParam = startLoc.context !is null && startLoc.context is endLoc.context;

        assert(start.context.name.among("^", "##"));
        auto locationContextX1 = context.getLocationContext(immutable(LocationContext)(start.context,
                nameToken.start.loc, nameToken.inputLength,
                funcMacroLocation.context.prev.name ~ "." ~ nameToken.content,
                goodParam ? startLoc.context.filename : ""));
        auto locationContextX = context.getLocationContext(immutable(LocationContext)(locationContextX1, goodParam
                ? startLoc.loc : LocationN.init, goodParam
                ? (endLoc.loc - startLoc.loc) : LocationN.LocationDiff.init,
                "^", commonLoc1.context.filename));

        context.locationContextInfoMap.getLocationContextInfo(locationContextX)
            .condition = condition;

        immutable(LocationContext)* mapLocationContext(immutable(LocationContext)* l)
        {
            assert(l !is null);
            if (l is commonLoc1.context)
                return locationContextX;
            auto r = context.getLocationContext(immutable(LocationContext)(mapLocationContext(l.prev),
                    l.startInPrev, l.lengthInPrev, l.name, l.filename));
            auto info = context.locationContextInfoMap.getLocationContextInfo(l);
            context.locationContextInfoMap.getLocationContextInfo(r)
                .sourceTokens = info.sourceTokens;
            context.locationContextInfoMap.getLocationContextInfo(l).mappedInParam = true;
            if (info.condition !is null)
                context.locationContextInfoMap.getLocationContextInfo(r)
                    .condition = context.logicSystem.and(condition, info.condition);
            return r;
        }

        auto mappedLocationContext = mapLocationContext(t2.t.start.context);
        LocationX location2 = LocationX(t2.t.start.loc, mappedLocationContext);

        r ~= tuple!(Tree, Location)(t2.t, location2);
    }
    return r;
}

Tuple!(Tree, Location)[] replaceMacroConcat(ParserWrapper)(Location start, Tree t, MacroParam[string] paramMap,
        Context!(ParserWrapper) context, Location funcMacroLocation, immutable(Formula)* condition)
{
    assert(t.name == "ParamConcat");
    Tuple!(Tree, Location)[][] tokenLists;
    Tree[] concatTokens;

    assert(t.start.context.filename == start.context.filename);
    auto locationContextX0 = context.getLocationContext(immutable(LocationContext)(start.context,
            t.start.loc, t.inputLength, "##", start.context.filename));
    start = Location(start.loc, locationContextX0);

    void analyzeTree(Location start, Tree t)
    {
        Tree lhsTree = t.childs[0];
        Tree rhsTree = t.childs[2];
        if (lhsTree.name == "ParamConcat")
        {
            analyzeTree(start, lhsTree);
        }
        else if (lhsTree.childs[0].content in paramMap)
        {
            Tree nameToken = lhsTree.childs[0];
            tokenLists ~= mapParams(start, nameToken, paramMap, context,
                    funcMacroLocation, condition);
        }
        else
            tokenLists ~= [
                tuple!(Tree, Location)(lhsTree.childs[0],
                        reparentLocation(lhsTree.start, start.context))
            ];

        Tree middleChild = Tree(t.childs[1].childs[0].content, SymbolID.max,
                ProductionID.max, NodeType.token, []);
        middleChild.setStartEnd(reparentLocation(t.childs[1].start,
                start.context), reparentLocation(t.childs[1].end, start.context));
        concatTokens ~= middleChild;

        if (rhsTree.childs[0].content in paramMap)
        {
            Tree nameToken = rhsTree.childs[0];
            tokenLists ~= mapParams(start, nameToken, paramMap, context,
                    funcMacroLocation, condition);
        }
        else
            tokenLists ~= [
                tuple!(Tree, Location)(rhsTree.childs[0],
                        reparentLocation(rhsTree.start, start.context))
            ];
    }

    analyzeTree(start, t);

    Tree[] newChilds;
    foreach (i; 0 .. tokenLists.length)
    {
        if (i)
            newChilds ~= concatTokens[i - 1];

        Tree[] newChildsLeft;
        foreach (t2; tokenLists[i])
        {
            Tree token = Tree(t2[0].content, SymbolID.max, ProductionID.max, NodeType.token, []);
            token.setStartEnd(t2[1], t2[1] + t2[0].inputLength);
            newChildsLeft ~= token;
        }
        Tree arrLeft = createArrayTree(newChildsLeft);

        auto grammarInfo = getDummyGrammarInfo("ParamConcatPart");
        Tree part = Tree("ParamConcatPart", grammarInfo.startNonterminalID,
                grammarInfo.startProductionID, NodeType.nonterminal, [arrLeft]);
        part.grammarInfo = grammarInfo;

        newChilds ~= part;
    }
    Tree arr = createArrayTree(newChilds);
    auto grammarInfo = getDummyGrammarInfo("ParamConcat");
    Tree sourceTokens = Tree("ParamConcat", grammarInfo.startNonterminalID,
            grammarInfo.startProductionID, NodeType.nonterminal, [arr]);
    sourceTokens.grammarInfo = grammarInfo;
    context.locationContextInfoMap.getLocationContextInfo(locationContextX0)
        .sourceTokens = sourceTokens;
    context.locationContextInfoMap.getLocationContextInfo(locationContextX0).condition = condition;

    Tuple!(Tree, Location)[] r;
    for (size_t i = 0; i + 1 < tokenLists.length; i++)
    {
        if (tokenLists[i].length)
            r ~= tokenLists[i][0 .. $ - 1];

        string newText;
        if (tokenLists[i].length)
            newText = tokenLists[i][$ - 1][0].content;
        size_t multiTokenIndex = size_t.max;
        size_t multiTokenNum = 0;
        if (tokenLists[i].length > 1 || (i && tokenLists[i].length >= 1))
        {
            multiTokenNum++;
            multiTokenIndex = i;
        }
        while (i + 1 < tokenLists.length)
        {
            if (tokenLists[i + 1].length > 1)
            {
                multiTokenNum++;
                multiTokenIndex = i + 1;
            }
            if (tokenLists[i + 1].length)
            {
                newText ~= tokenLists[i + 1][0][0].content;
                tokenLists[i + 1] = tokenLists[i + 1][1 .. $];
            }
            if (tokenLists[i + 1].length > 0)
                break;

            i++;
        }

        assert(t.childs[1].start.context.filename == start.context.filename);
        immutable(LocationContext)* locationContextX;

        if (start.context !in context.locationUniqueNumbers)
            context.locationUniqueNumbers[start.context] = 0;
        context.locationUniqueNumbers[start.context]++;

        locationContextX = context.getLocationContext(immutable(LocationContext)(start.context,
                t.childs[1].start.loc, t.childs[1].inputLength, "##",
                text("@concat", context.locationUniqueNumbers[start.context])));

        Location newStart = Location(LocationN.init, locationContextX);
        Tree newToken = Tree(newText, SymbolID.max, ProductionID.max, NodeType.token, []);
        newToken.setStartEnd(newStart, newStart + Location.LocationDiff.fromStr(newText));
        r ~= tuple!(Tree, Location)(newToken, newStart);
    }
    r ~= tokenLists[$ - 1];

    return r;
}

void processToken(ParserWrapper)(Location start, Tree token,
        Context!(ParserWrapper) context, immutable Formula* condition,
        ref ParallelParser!(ParserWrapper) parallelParser, bool isNextParen,
        MacroParam[string] paramMap, Location funcMacroLocation,
        bool[string] macrosDone, ParallelParser!(ParserWrapper) parentParser, bool argPrescan)
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
    Tree nameToken;
    if (token.nonterminalID == preprocNonterminalIDFor!"ParamExpansion" || token.name == "ParamConcat")
        nameToken = Tree.init;
    else
        nameToken = token.childs[0];

    if (nameToken.isValid && nameToken.content in paramMap)
    {
        foreach (i, x; mapParams(start, nameToken, paramMap, context,
                funcMacroLocation, condition))
        {
            auto t2 = paramMap[nameToken.content].tokens[i];
            bool isNextParen2;
            if (i + 1 < paramMap[nameToken.content].tokens.length)
                isNextParen2 = paramMap[nameToken.content].tokens[i + 1].t.content == "(";
            else
                isNextParen2 = isNextParen;

            parallelParser = expandMacros(context, x[0], x[1], condition,
                    t2.macrosDone, isNextParen2, parallelParser, parentParser, true);

            if (parentParser is null)
                context.checkReferences();
            tryMergeParser(parallelParser, condition, context, parentParser);
            if (parentParser is null)
                context.checkReferences();
        }
    }
    else
    {
        if (token.nonterminalID == preprocNonterminalIDFor!"ParamExpansion")
        {
            string name = token.childs[2].content;

            assert(start.context.name == "^");

            string newText = "\"";
            ParamToken[] paramTokens;
            if (name in paramMap)
                paramTokens = paramMap[name].tokens;
            foreach (i, t2; paramTokens)
            {
                if (i && t2.t.start > paramTokens[i - 1].t.end)
                {
                    newText ~= " ";
                }
                newText ~= t2.t.content.escapeD;
            }
            newText ~= "\"";

            Tree newToken = Tree(newText, SymbolID.max, ProductionID.max, NodeType.token, []);

            assert(token.start.context.filename == start.context.filename);
            auto locationContextX0 = context.getLocationContext(immutable(LocationContext)(start.context,
                    token.start.loc, token.inputLength, "#", start.context.filename));

            Tree firstChild = Tree(token.childs[0].content, SymbolID.max,
                    ProductionID.max, NodeType.token, []);
            firstChild.setStartEnd(start,
                    start + LocationN.LocationDiff.fromStr(token.childs[0].content));
            Tree[] newChilds;
            foreach (i, t2; paramTokens)
                newChilds ~= t2.t;
            Tree arr = createArrayTree(newChilds);
            auto grammarInfo = getDummyGrammarInfo("ParamExpansion");
            Tree sourceTokens = Tree("ParamExpansion", grammarInfo.startNonterminalID,
                    grammarInfo.startProductionID, NodeType.nonterminal, [firstChild, arr]);
            sourceTokens.grammarInfo = grammarInfo;
            context.locationContextInfoMap.getLocationContextInfo(locationContextX0)
                .sourceTokens = sourceTokens;
            context.locationContextInfoMap.getLocationContextInfo(locationContextX0)
                .condition = condition;

            auto locationContextX1 = context.getLocationContext(immutable(LocationContext)(locationContextX0,
                    start.loc, token.inputLength, start.context.prev.name ~ "." ~ name, ""));
            auto locationContextX = context.getLocationContext(
                    immutable(LocationContext)(locationContextX1, LocationN.init,
                    LocationN.LocationDiff.init, "^", funcMacroLocation.context.filename));

            context.locationContextInfoMap.getLocationContextInfo(locationContextX)
                .condition = condition;

            LocationN start2, end2;
            if (name in paramMap && paramMap[name].tokens.length)
            {
                start2 = paramMap[name].tokens[0].t.start.loc;
                end2 = paramMap[name].tokens[$ - 1].t.end.loc;
            }

            newToken.setStartEnd(LocationX(start2, locationContextX),
                    LocationX(end2, locationContextX));
            processDirectToken(LocationX(start2, locationContextX), newToken,
                    context, parallelParser, condition, macrosDone, false, parentParser);
        }
        else if (token.name == "ParamConcat")
        {
            auto replacedTokens = replaceMacroConcat(start, token, paramMap,
                    context, funcMacroLocation, condition);
            foreach (i, t2; replacedTokens)
            {
                processDirectToken(t2[1], t2[0], context, parallelParser, condition,
                        macrosDone, i == replacedTokens.length - 1 && isNextParen, parentParser);
            }
        }
        else
        {
            if (argPrescan)
                parallelParser = expandMacros(context, token.childs[0], start, condition,
                        macrosDone, isNextParen, parallelParser, parentParser, true);
            else
                processDirectToken(start, token.childs[0], context, parallelParser,
                        condition, macrosDone, isNextParen, parentParser);
        }
    }
}
