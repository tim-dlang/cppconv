
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.treematching;
import cppconv.cppparserwrapper;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.conv;
import std.string;
import std.traits;

struct MatchFunc(alias F)
{
    alias Func = F;
    enum immutable(ProductionID[]) PossibleProductionIds = [];
    static void generateMatchCode(ref CodeWriter code, string treeName, string matcher, size_t index)
    {
        if (code.data.length)
            code.write(" && ");
        code.write(matcher, ".Func()");
    }
}

bool simpleGlob(string s, string pattern)
{
    if (pattern.canFind("*"))
    {
        auto parts = pattern.split("*");
        assert(parts.length == 2);

        if (s.startsWith(parts[0]) && s.endsWith(parts[1]))
        {
            return true;
        }
    }
    else
    {
        if (s == pattern)
        {
            return true;
        }
    }
    return false;
}

struct MatchNonterminals(M...)
{
    enum immutable(ProductionID[]) PossibleProductionIds = () {
        immutable(ProductionID)[] r;

        size_t[] counts;
        counts.length = M.length;
        foreach (k, p; ParserWrapper.allProductions)
        {
            if (p.nonterminalID != NonterminalID.invalid)
            {
                string nonterminalName = ParserWrapper.allNonterminals[p.nonterminalID.id
                    - ParserWrapper.startNonterminalID].name;

                bool use;
                foreach (i, m; M)
                {
                    if (nonterminalName.simpleGlob(m))
                    {
                        use = true;
                        counts[i]++;
                    }
                }
                if (use)
                {
                    r ~= cast(ProductionID)(k + ParserWrapper.startProductionID);
                }
            }
        }
        foreach (i, m; M)
        {
            assert(counts[i], text("cound not find ", m));
        }
        assert(r.length);
        return r;
    }();
    static void generateMatchCode(ref CodeWriter code, string treeName, string matcher, size_t index)
    {
    }
}

struct MatchProductions(alias F)
{
    enum immutable(ProductionID[]) PossibleProductionIds = () {
        immutable(ProductionID)[] r;

        foreach (k, p; ParserWrapper.allProductions)
        {
            if (p.nonterminalID != NonterminalID.invalid)
            {
                string nonterminalName = ParserWrapper.allNonterminals[p.nonterminalID.id
                    - ParserWrapper.startNonterminalID].name;
                string[] symbolNames;
                foreach (s; p.symbols)
                {
                    if (s.isToken)
                        symbolNames ~= ParserWrapper.allTokens[s.toTokenID.id].name;
                    else
                        symbolNames ~= ParserWrapper.allNonterminals[s.toNonterminalID.id].name;
                }

                bool use = !!F(p, nonterminalName, symbolNames);
                if (use)
                {
                    r ~= cast(ProductionID)(k + ParserWrapper.startProductionID);
                }
            }
        }
        assert(r.length);
        return r;
    }();
    static void generateMatchCode(ref CodeWriter code, string treeName, string matcher, size_t index)
    {
    }
}

struct MatchProductionId(size_t productionID)
{
    enum immutable(ProductionID[]) PossibleProductionIds = [productionID];
    static void generateMatchCode(ref CodeWriter code, string treeName, string matcher, size_t index)
    {
    }
}

struct MatchRealParentNonterminals(M...)
{
    enum immutable(ProductionID[]) PossibleProductionIds = [];
    static void generateMatchCode(ref CodeWriter code, string treeName, string matcher, size_t index)
    {
        if (code.data.length)
            code.write(" && ");
        code.write("realParent.isValid");

        code.write(" && (");
        bool first = true;
        size_t[] counts;
        counts.length = M.length;
        foreach (k, m2; ParserWrapper.allNonterminals)
        {
            string nonterminalName = m2.name;
            size_t nonterminalID = ParserWrapper.startNonterminalID + k;
            bool use;
            foreach (i, m; M)
            {
                if (nonterminalName.simpleGlob(m))
                {
                    use = true;
                    counts[i]++;
                }
            }
            if (use)
            {
                if (!first)
                    code.write(" || ");
                first = false;
                code.write("realParent", ".nonterminalID == ", nonterminalID,
                        "/* ", nonterminalName, " */");
            }
        }
        foreach (i, m; M)
        {
            assert(counts[i], text("cound not find ", m));
        }
        code.write(")");
    }
}

static const(char)[] generateMatchTreeCode(Funcs...)()
{
    CodeWriter code;

    struct Bucket
    {
        immutable(ProductionID)[] productions;
        immutable(ProductionID)[][] productions2;
        size_t[] funcs;
        const(char)[][] codes;
    }

    Bucket[] buckets;
    size_t[size_t] bucketByProductionID;
    foreach (i, F; Funcs)
    {
        alias Params = ParameterTypeTuple!F;

        immutable(ProductionID)[] productions;
        foreach (index, P; Params)
        {
            enum PossibleProductionIds = P.PossibleProductionIds;
            if (PossibleProductionIds.length == 0)
                continue;
            else if (productions.length == 0)
                productions = PossibleProductionIds;
            else
            {
                immutable(ProductionID)[] productionsBak = productions;
                productions = [];
                foreach (p; productionsBak)
                    if (PossibleProductionIds.canFind(p))
                        productions ~= p;
            }
        }

        assert(productions.length || (Params.length == 0 && i + 1 == Funcs.length));

        size_t bucketId = size_t.max;
        foreach (p; productions)
        {
            if (p in bucketByProductionID)
            {
                size_t bucketId2 = bucketByProductionID[p];
                if (bucketId != size_t.max && bucketId != bucketId2)
                {
                    buckets[bucketId].funcs ~= buckets[bucketId2].funcs;
                    buckets[bucketId].codes ~= buckets[bucketId2].codes;
                    buckets[bucketId].productions2 ~= buckets[bucketId2].productions2;
                    buckets[bucketId].productions.addOnce(buckets[bucketId2].productions);
                    foreach (p2; buckets[bucketId2].productions)
                        bucketByProductionID[p2] = bucketId;
                    buckets[bucketId2] = Bucket.init;
                }
                else
                    bucketId = bucketId2;
            }
        }
        if (bucketId == size_t.max)
        {
            bucketId = buckets.length;
            buckets.length++;
        }
        foreach (p; productions)
        {
            buckets[bucketId].productions.addOnce(p);
            bucketByProductionID[p] = bucketId;
        }

        CodeWriter code2;
        foreach (index, P; Params)
        {
            P.generateMatchCode(code2, "tree", text("params[", index, "]"), index);
        }
        buckets[bucketId].funcs ~= i;
        buckets[bucketId].codes ~= code2.data;
        buckets[bucketId].productions2 ~= productions;
    }

    code.writeln("switch (tree.productionID)");
    code.writeln("{").incIndent;
    foreach (bucket; buckets)
    {
        if (bucket.funcs.length == 0)
            continue;
        foreach (p; bucket.productions)
            code.writeln("case ", p, ":");
        if (bucket.productions.length == 0)
            code.writeln("default:");
        code.incIndent;
        bool reachable = true;
        foreach (i; 0 .. bucket.funcs.length)
        {
            bool always = true;
            if (bucket.productions2[i].length != bucket.productions.length)
            {
                code.write("if (");
                bool firstP = true;
                string productionsCode;
                foreach (p; bucket.productions2[i])
                {
                    if (!firstP)
                        productionsCode ~= " || ";
                    firstP = false;
                    productionsCode ~= text("tree", ".productionID == ", p);
                }
                code.write(productionsCode);
                assert(!firstP);
                code.writeln(")");
                always = false;
            }
            code.writeln("{").incIndent;
            code.writeln("alias F = Funcs[", bucket.funcs[i], "];");
            code.writeln("alias Params = ParameterTypeTuple!F;");

            code.writeln("Params params;");

            if (bucket.codes[i] != "")
            {
                always = false;
                code.write("if (");
                code.write(bucket.codes[i]);
                code.writeln(")");
                code.writeln("{").incIndent;
            }

            code.writeln("F(params);");
            code.writeln("return;");

            if (bucket.codes[i] != "")
                code.decIndent.writeln("}");
            code.decIndent.writeln("}");
            if (always)
                reachable = false;
        }
        if (!reachable)
            code.writeln("assert(false);").decIndent;
        else if (bucket.productions.length == 0)
            code.writeln("break;").decIndent;
        else
            code.writeln("goto default;").decIndent;
    }
    code.decIndent.writeln("}");
    return code.data;
}

void matchTree(Funcs...)(Tree tree, Tree realParent)
{
    mixin(generateMatchTreeCode!Funcs());
    assert(false);
}

const(char)[] matchTreePatternGenCode(string pattern, immutable GrammarInfo* grammarInfo, bool debugWrite)
{
    import P = cppconv.grammartreematching;
    static import cppconv.grammartreematching_lexer;
    import dparsergen.core.dynamictree;
    import dparsergen.core.location;

    alias Location = LocationAll;
    alias L = cppconv.grammartreematching_lexer.Lexer!Location;
    alias Creator = DynamicParseTreeCreator!(P, Location, LocationRangeStartLength);
    alias Tree = DynamicParseTree!(Location, LocationRangeStartLength);
    alias nonterminalIDFor = P.nonterminalIDFor;

    SymbolID[string] nonterminalByName;
    foreach (i, info; grammarInfo.allNonterminals)
    {
        nonterminalByName[info.name] = cast(SymbolID) (i + grammarInfo.startNonterminalID);
    }

    auto creator = new Creator;
    auto tree = P.parse!(Creator, L, "PatternOr")(pattern, creator);

    CodeWriter code;
    int id;

    bool isProductionPossible(Tree[] childPatterns, size_t wildcard2Pos, immutable Production* production)
    {
        if (wildcard2Pos == size_t.max && production.symbols.length != childPatterns.length)
            return false;
        if (wildcard2Pos != size_t.max && production.symbols.length < childPatterns.length)
            return false;
        code.writeln("    // Check production ", production.nonterminalID, " ", production.symbols.length);
        foreach (i; 0 .. childPatterns.length)
        {
            auto c = childPatterns[i].childs[$ - 1];
            size_t k = i;
            if (i >= wildcard2Pos)
            {
                k = i + production.symbols.length - childPatterns.length;
            }
            if (c.nonterminalID == nonterminalIDFor!"PatternString")
            {
                if (production.symbols[i].isToken)
                {
                    auto tokenInfo = &grammarInfo.allTokens[production.symbols[k].toTokenID.id];
                    code.writeln("    // Symbol ", i, " token ", tokenInfo.name, " ", c.childs[0].content);
                    if (tokenInfo.name.startsWith("\"") && tokenInfo.name != c.childs[0].content)
                        return false;
                }
                else
                {
                    auto nonterminalInfo = &grammarInfo.allNonterminals[production.symbols[k].toNonterminalID.id];
                    code.writeln("    // Symbol ", i, " nonterminal as string ", nonterminalInfo.name, " ", c.childs[0].content);
                    if ((nonterminalInfo.flags & NonterminalFlags.string) == 0)
                        return false;
                }
            }
            else if (c.nonterminalID == nonterminalIDFor!"PatternNonterminal")
            {
                if (production.symbols[i].isToken)
                {
                    return false;
                }
                auto nonterminalInfo = &grammarInfo.allNonterminals[production.symbols[k].toNonterminalID.id];
                code.writeln("    // Symbol ", i, " nonterminal ", nonterminalInfo.name, " ", c.childs[0].content);
                if ((nonterminalInfo.flags & NonterminalFlags.nonterminal) == 0)
                    return false;
                if (!nonterminalInfo.buildNonterminals.canFind(nonterminalByName[c.childs[0].content]))
                    return false;
            }
            else if (c.nonterminalID == nonterminalIDFor!"PatternArray")
            {
                if (production.symbols[i].isToken)
                {
                    return false;
                }
                auto nonterminalInfo = &grammarInfo.allNonterminals[production.symbols[k].toNonterminalID.id];
                code.writeln("    // Symbol ", i, " array ", nonterminalInfo.name);
                if ((nonterminalInfo.flags & NonterminalFlags.array) == 0)
                    return false;
            }
        }
        return true;
    }

    string visitPattern(Tree tree, string paramCode)
    {
        if (tree.nonterminalID == nonterminalIDFor!"PatternOr")
            return "(" ~ visitPattern(tree.childs[0], paramCode) ~ " || " ~ visitPattern(tree.childs[2], paramCode) ~ ")";

        int idHere = id;
        id++;

        string savedName;
        if (tree.childs.length == 3)
            savedName = tree.childs[0].content;

        string funcName;
        if (savedName)
            funcName = "match" ~ savedName;
        else
            funcName = text("match", idHere);

        tree = tree.childs[$ - 1];

        Tree[] childPatterns;
        size_t wildcard2Pos = size_t.max;
        void addChildPatterns(Tree[] childs)
        {
                foreach (c; childs)
                {
                    if (c !is null && !c.isToken)
                    {
                        if (c.childs[$ - 1].nonterminalID == nonterminalIDFor!"PatternWildcard2")
                        {
                            if (wildcard2Pos != size_t.max)
                                throw new Exception("Multiple \"...\" not supported.");
                            wildcard2Pos = childPatterns.length;
                        }
                        else
                            childPatterns ~= c;
                    }
                }
        }
        if (tree.nonterminalID == nonterminalIDFor!"PatternNonterminal")
        {
            if (tree.childs.length > 1)
            {
                addChildPatterns(tree.childs[2].childs);
            }
        }
        else if (tree.nonterminalID == nonterminalIDFor!"PatternArray")
        {
            addChildPatterns(tree.childs[1].childs);
        }
        else if (!savedName && tree.nonterminalID == nonterminalIDFor!"PatternString")
        {
            return text("(", paramCode, ".isToken && ", paramCode, ".content == ", tree.childs[0].content, ")");
        }
        else if (!savedName && tree.nonterminalID == nonterminalIDFor!"PatternWildcard")
        {
            return text("true");
        }

        string[] childCodes;
        foreach (i, c; childPatterns)
            childCodes ~= visitPattern(c,
                i >= wildcard2Pos
                    ? text("tree.childs[$ - ", childPatterns.length - i, "]")
                    : text("tree.childs[", i, "]"));

        if (savedName)
            code.writeln("Tree saved", savedName, ";");
        code.writeln("// ", tree.toString());
        code.writeln("bool ", funcName, "(Tree tree)");
        code.writeln("{");
        if (debugWrite)
        {
            code.writeln("    import std.stdio: writeln;");
            code.writeln("    if (tree.isValid)");
            code.writeln("    {");
            code.writeln("        writeln(\"start ", funcName, " \", tree.nodeType, \" \", tree.nameOrContent, \" \", tree.nonterminalID, \" childs.length=\", tree.childs.length, \" \", tree);");
            code.writeln("        foreach (i, child; tree.childs)");
            code.writeln("        {");
            code.writeln("            if (child.isValid)");
            code.writeln("                writeln(\"  childs[\", i, \"]: \", child.nodeType, \" \", child.nameOrContent, \" \", child.nonterminalID, \" \", child);");
            code.writeln("            else");
            code.writeln("                writeln(\"  childs[\", i, \"]: null\");");
            code.writeln("        }");
            code.writeln("    }");
            code.writeln("    else");
            code.writeln("        writeln(\"start ", funcName, " null\");");
        }
        if (tree.nonterminalID == nonterminalIDFor!"PatternString")
        {
            code.writeln("    if (!tree.isValid || !tree.isToken || tree.content != ", tree.childs[0].content, ")");
            code.writeln("        return false;");
        }
        else if (tree.nonterminalID == nonterminalIDFor!"PatternNonterminal")
        {
            SymbolID nonterminalID = SymbolID.max;
            if (tree.childs[0].content in nonterminalByName)
                nonterminalID = nonterminalByName[tree.childs[0].content];
            else
                throw new Exception("Unknown nonterminal " ~ tree.childs[0].content);
            immutable Nonterminal *nonterminalInfo = &grammarInfo.allNonterminals[nonterminalID - grammarInfo.startNonterminalID];
            code.writeln("    if (!tree.isValid || tree.nodeType != NodeType.nonterminal || tree.nonterminalID != ", nonterminalID, " /* ", tree.childs[0].content, " */)");
            code.writeln("        return false;");
            if (tree.childs.length > 1)
            {
                bool possible;
                foreach (productionID; nonterminalInfo.firstProduction .. nonterminalInfo.firstProduction + nonterminalInfo.numProductions)
                {
                    immutable production = &grammarInfo.allProductions[productionID - grammarInfo.startProductionID];
                    assert(production.nonterminalID.id == nonterminalID);
                    if (isProductionPossible(childPatterns, wildcard2Pos, production))
                        possible = true;
                }
                if (!possible)
                    throw new Exception("No possible production found for pattern with nonterminal " ~ tree.childs[0].content);
                code.writeln("    if (tree.childs.length ", wildcard2Pos != size_t.max ? "<" : "!=", " ", childCodes.length, ")");
                code.writeln("        return false;");
                foreach (i, childCode; childCodes)
                {
                    if (childCode != "true")
                    {
                        code.writeln("    // ", childPatterns[i].toString());
                        code.writeln("    if (!", childCode, ")");
                        code.writeln("        return false;");
                    }
                }
            }
        }
        else if (tree.nonterminalID == nonterminalIDFor!"PatternArray")
        {
            if (childCodes.length == 0)
            {
                code.writeln("    if (tree.isValid)");
                code.writeln("    {").incIndent;
            }
            code.writeln("    if (!tree.isValid || tree.nodeType != NodeType.array)");
            code.writeln("        return false;");
            code.writeln("    if (tree.childs.length ", wildcard2Pos != size_t.max ? "<" : "!=", " ", childCodes.length, ")");
            code.writeln("        return false;");
            foreach (i, childCode; childCodes)
            {
                if (childCode != "true")
                {
                    code.writeln("    // ", childPatterns[i].toString());
                    code.writeln("    if (!", childCode, ")");
                    code.writeln("        return false;");
                }
            }
            if (childCodes.length == 0)
            {
                code.decIndent.writeln("    }");
            }
        }
        else if (tree.nonterminalID == nonterminalIDFor!"PatternNull")
        {
            code.writeln("    if (tree.isValid)");
            code.writeln("        return false;");
        }
        else if (tree.nonterminalID == nonterminalIDFor!"PatternWildcard")
        {
        }
        else
            assert(false, tree.name);
        if (savedName)
            code.writeln("    this.saved", savedName, " = tree;");
        if (debugWrite)
            code.writeln("    writeln(\"end ", funcName, " \");");
        code.writeln("    return true;");
        code.writeln("}\n");
        return text(funcName, "(", paramCode, ")");
    }
    string firstCode = visitPattern(tree, "tree");
    code.writeln("bool doMatch(Tree tree)");
    code.writeln("{");
    code.writeln("    return ", firstCode, ";");
    code.writeln("}");

    return code.data;
}

template TreePattern(alias GrammarModule, Tree)
{
    struct PatternMatcher(string pattern, bool debugWrite = false)
    {
        mixin(matchTreePatternGenCode(pattern, &GrammarModule.grammarInfo, debugWrite));

        bool hasMatch;

        @safe bool opCast(T:bool)() const nothrow
        {
            return hasMatch;
        }

        PatternMatcher opBinary(string op)(bool rhs) if (op == "&")
        {
            if (!hasMatch)
                return this;
            if (rhs)
                return this;
            return PatternMatcher.init;
        }
    }

    PatternMatcher!pattern matchTreePattern(string pattern)(Tree tree)
    {
        PatternMatcher!pattern matcher;
        matcher.hasMatch = matcher.doMatch(tree);
        return matcher;
    }

    PatternMatcher!(pattern, true) matchTreePatternDebug(string pattern)(Tree tree)
    {
        pragma(msg, matchTreePatternGenCode(pattern, &GrammarModule.grammarInfo, true));

        PatternMatcher!(pattern, true) matcher;
        matcher.hasMatch = matcher.doMatch(tree);
        return matcher;
    }
}
