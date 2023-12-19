
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.treematching;
import cppconv.cppparserwrapper;
import dparsergen.core.grammarinfo;
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
