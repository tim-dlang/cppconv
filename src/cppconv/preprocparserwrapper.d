
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.preprocparserwrapper;
import cppconv.cpptree;
static import cppconv.grammarcpreproc_lexer;
import cppconv.locationstack;
import cppconv.stringtable;
import cppconv.utils;
import dparsergen.core.grammarinfo;

private alias Location = LocationX;

static import cppconv.grammarcpreproc;

alias P1 = cppconv.grammarcpreproc;
private alias L1 = cppconv.grammarcpreproc_lexer.Lexer!Location;

static assert(P1.allTokens.length < 1000);
static assert(P1.allNonterminals.length < 1000);
static assert(P1.allProductions.length < 1000);

alias preprocNonterminalIDFor = P1.nonterminalIDFor;

CppParseTree preprocParse(string inText, LocationX location, SimpleClassAllocator!(
        CppParseTreeStruct*) allocator, StringTable!(ubyte[0])* stringPool)
{
    CppParseTreeCreator!(P1) creator;
    creator.allocator = allocator;
    creator.stringPool = stringPool;
    return P1.parse!(CppParseTreeCreator!(P1), L1)(inText, creator, location);
}

CppParseTree preprocParseTokenList(string inText, LocationX location,
        SimpleClassAllocator!(CppParseTreeStruct*) allocator, StringTable!(ubyte[0])* stringPool)
{
    CppParseTreeCreator!(P1) creator;
    creator.allocator = allocator;
    creator.stringPool = stringPool;
    return P1.parse!(CppParseTreeCreator!(P1), L1, "TokenList")(inText, creator, location);
}

immutable GrammarInfo* preprocGrammarInfo = &P1.grammarInfo;
