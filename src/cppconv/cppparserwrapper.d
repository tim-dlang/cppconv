
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppparserwrapper;
import cppconv.common;
import cppconv.cpptree;
import cppconv.locationstack;
import cppconv.parallelparser;
import cppconv.stringtable;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.parseexception;
import cppconv.codewriter;
import std.algorithm;
import std.conv;
import std.stdio;

alias Location = LocationX;

static import cppconv.grammarcpp;

alias P2 = cppconv.grammarcpp;
static import cppconv.grammarcpp_lexer;

alias L2 = cppconv.grammarcpp_lexer.Lexer!Location;

/*static assert(P1.allTokens.length < 1000);
static assert(P1.allNonterminals.length < 1000);
static assert(P1.allProductions.length < 1000);*/
static assert(P2.allTokens.length < 1000);
static assert(P2.allNonterminals.length < 1000);
static assert(P2.allProductions.length < 1200);

// https://en.cppreference.com/w/c/keyword
enum CKeywords = [
    "auto",
    "break",
    "case",
    "char",
    "const",
    "continue",
    "default",
    "do",
    "double",
    "else",
    "enum",
    "extern",
    "float",
    "for",
    "goto",
    "if",
    "inline", // (since C99)
    "int",
    "long",
    "register",
    "restrict", // (since C99)
    "return",
    "short",
    "signed",
    "sizeof",
    "static",
    "struct",
    "switch",
    "typedef",
    "union",
    "unsigned",
    "void",
    "volatile",
    "while",
];

struct ParserWrapper
{
    P2.PushParser!(CppParseTreeCreator!(P2), string) pushParser;
    bool isCPlusPlus;

    alias allNonterminals = P2.allNonterminals;
    alias allTokens = P2.allTokens;
    alias allProductions = P2.allProductions;
    alias grammarInfo = P2.grammarInfo;

    alias StackNode = typeof(pushParser).StackNode;
    alias StackEdge = typeof(pushParser).StackEdge;
    alias StackEdgeData = typeof(pushParser).StackEdgeData;
    alias nonterminalIDFor = P2.nonterminalIDFor;
    static bool nonterminalIDAmong(names...)(SymbolID id)
    {
        foreach (name; names)
            if (id == P2.nonterminalIDFor!name)
                return true;
        return false;
    }

    enum startNonterminalID = P2.startNonterminalID;
    enum endNonterminalID = P2.endNonterminalID;
    enum startProductionID = P2.startProductionID;

    void startParseTranslationUnit(SimpleClassAllocator!(CppParseTreeStruct*) allocator,
            StringTable!(ubyte[0])* stringPool)
    {
        pushParser.creator.allocator = allocator;
        pushParser.creator.stringPool = stringPool;
        pushParser.startParseTranslationUnit();
    }

    void startParseExpression(SimpleClassAllocator!(CppParseTreeStruct*) allocator,
            StringTable!(ubyte[0])* stringPool)
    {
        pushParser.creator.allocator = allocator;
        pushParser.creator.stringPool = stringPool;
        pushParser.startParseExpression();
    }

    static string[] splitTokens(string str)
    {
        string[] r;
        L2 lexer = L2(str);

        while (!lexer.empty)
        {
            r ~= lexer.front.content;
            lexer.popFront();
        }
        return r;
    }

    void pushToken(string token, Location start)
    {
        L2 lexer = L2(token);
        lexer.front.currentLocation = start;

        if (lexer.empty)
        {
            throw new SingleParseException!Location("can't lex token", Location.init, Location.init);
        }
        while (!lexer.empty)
        {
            SymbolID symbolID = P2.translateTokenIdFromLexer!L2(lexer.front.symbol);

            if (!isCPlusPlus)
            {
                switch (symbolID)
                {
                    mixin(() {
                        string r;
                        foreach (i, t; P2.allTokens)
                        {
                            if (t.name[0] != '\"')
                                continue;
                            if (t.name[1] < 'a' || t.name[1] > 'z')
                                continue;
                            if (CKeywords.canFind(t.name[1 .. $ - 1]))
                                continue;
                            r ~= text("case ", P2.startTokenID + i, ": // ", t.name, "\n");
                        }
                        r ~= q{symbolID = P2.getTokenID!"Identifier";};
                        r ~= "\nbreak;\ndefault:\n";
                        return r;
                    }());
                }
            }

            pushParser.pushToken(symbolID, lexer.front.content,
                    lexer.front.currentLocation, lexer.front.currentTokenEnd);
            lexer.popFront();
        }
        if (lexer.input.length)
        {
            throw new SingleParseException!Location("token not completely parsed",
                    Location.init, Location.init);
        }
    }

    void pushEnd()
    {
        pushParser.pushEnd();
    }

    void dumpStates(LogicSystem logicSystem, string indent)
    {
        cppconv.parallelparser.dumpStates!P2(pushParser, logicSystem, indent);
    }

    static bool canMerge(ref ParserWrapper pushParserA, ref ParserWrapper pushParserB)
    {
        return cppconv.parallelparser.canMerge!P2(pushParserA.pushParser, pushParserB.pushParser);
    }

    static void doMerge(ref ParserWrapper pushParserA,
            ref ParserWrapper pushParserB, ref ParserWrapper pushParserOut, immutable(
                Formula)*[2] childConditions2, LogicSystem logicSystem,
            immutable(Formula)* anyErrorCondition, immutable(Formula)* contextCondition)
    {
        cppconv.parallelparser.doMerge!P2(pushParserA.pushParser, pushParserB.pushParser,
                pushParserOut.pushParser, childConditions2, logicSystem,
                anyErrorCondition, contextCondition);
    }

    Tree getAcceptedExpression()
    {
        assert(pushParser.stackTops.length == 0, text(pushParser.stackTops));
        assert(pushParser.acceptedStackTops.length <= 1);
        Tree pt;
        if (pushParser.acceptedStackTops.length)
        {
            pt = pushParser.getParseTree!"Expression";
            return pt;
        }
        else
        {
            throw new Exception("no tree");
        }
    }

    Tree getAcceptedTranslationUnit()
    {
        assert(pushParser.stackTops.length == 0, text(pushParser.stackTops));
        assert(pushParser.acceptedStackTops.length <= 1, text(pushParser.acceptedStackTops));
        Tree pt;
        if (pushParser.acceptedStackTops.length)
        {
            pt = pushParser.getParseTree!"TranslationUnit";
        }
        return pt;
    }
}

alias nonterminalIDFor = ParserWrapper.nonterminalIDFor;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

enum INCLUDE_TREE_NONTERMINAL_ID = 20003;
enum INCLUDE_TREE_PRODUCTION_ID = 20004;

immutable IncludeTreeAllNonterminals = [
    immutable(Nonterminal)("@#IncludeDecl", NonterminalFlags.nonterminal, [],
            [INCLUDE_TREE_NONTERMINAL_ID]),
];

immutable IncludeTreeAllProductions = [
    immutable(Production)(immutable(NonterminalID)(INCLUDE_TREE_NONTERMINAL_ID)),
];

immutable GrammarInfo includeTreeGrammarInfo = immutable(GrammarInfo)(0, INCLUDE_TREE_NONTERMINAL_ID,
        INCLUDE_TREE_PRODUCTION_ID, [], IncludeTreeAllNonterminals, IncludeTreeAllProductions);
