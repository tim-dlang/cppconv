
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.preproc;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppparallelparser;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.filecache;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import std.algorithm;
import std.conv;
import std.exception;
import std.regex;
import std.stdio;

alias Location = LocationX;

alias Tree = CppParseTree;

class Define
{
    immutable(Formula)* condition;
    bool isFunctionLike;
    Tree definition;
    bool definedBeforeInclude;
    Define dup()
    {
        Define r = new Define;
        r.condition = condition;
        r.isFunctionLike = isFunctionLike;
        r.definition = definition;
        r.definedBeforeInclude = definedBeforeInclude;
        return r;
    }
}

class DefineSet
{
    Define[] defines;
    immutable(Formula)* conditionUnknown;
    immutable(Formula)* conditionUndef;
    string name;
    string currentVersion;
    immutable(Formula)* currentVersionLiteral;
    bool locked;
    bool used;
    bool beforeMainFile;

    this(LogicSystem logicSystem, string name)
    {
        this.name = name;

        conditionUnknown = logicSystem.literal(text("defined(", name, ")"));
        conditionUndef = logicSystem.notLiteral(text("defined(", name, ")"));
    }

    immutable(Formula)* conditionDefined(LogicSystem logicSystem)
    {
        return logicSystem.simplify(logicSystem.or(conditionUndef, conditionUnknown).negated);
    }

    void update(LogicSystem logicSystem, immutable(Formula)* condition,
            bool isFunctionLike, Tree definition)
    {
        if (locked)
            condition = logicSystem.false_;
        with (logicSystem)
        {
            foreach (d; defines)
            {
                d.condition = simplify(and(d.condition, not(condition)));
            }
            conditionUnknown = simplify(and(conditionUnknown, not(condition)));
            conditionUndef = simplify(and(conditionUndef, not(condition)));

            foreach (d; defines)
            {
                if (d.isFunctionLike == isFunctionLike && d.definition is definition)
                {
                    d.condition = simplify(distributeOrSimple(d.condition, condition));
                    d.definedBeforeInclude = false;
                    return;
                }
            }

            defines ~= new Define;
            defines[$ - 1].condition = condition;
            defines[$ - 1].isFunctionLike = isFunctionLike;
            defines[$ - 1].definition = definition;
        }
    }

    void updateUndef(LogicSystem logicSystem, immutable(Formula)* condition)
    {
        if (locked)
            condition = logicSystem.false_;
        with (logicSystem)
        {
            foreach (d; defines)
            {
                d.condition = simplify(and(d.condition, not(condition)));
            }
            conditionUnknown = simplify(and(conditionUnknown, not(condition)));
            conditionUndef = simplify(or(conditionUndef, condition));
        }
    }

    void updateUnknown(LogicSystem logicSystem, immutable(Formula)* condition)
    {
        if (locked)
            condition = logicSystem.false_;
        with (logicSystem)
        {
            foreach (d; defines)
            {
                d.condition = simplify(and(d.condition, not(condition)));
            }
            conditionUnknown = simplify(or(conditionUnknown, condition));
            conditionUndef = simplify(and(conditionUndef, not(condition)));
        }
    }

    void mergeDuplicates(LogicSystem logicSystem)
    {
        size_t outIndex;
        size_t[LocationX] byLoc;
        foreach (i, d; defines)
        {
            if (d.definition.start in byLoc)
            {
                auto k = byLoc[d.definition.start];
                defines[k].condition = logicSystem.simplify(logicSystem.or(defines[k].condition,
                        d.condition));
                continue;
            }
            defines[outIndex] = d;
            byLoc[d.definition.start] = outIndex;
            outIndex++;
        }
        defines = defines[0 .. outIndex];
    }

    DefineSet dup(LogicSystem logicSystem)
    {
        DefineSet r = new DefineSet(logicSystem, name);
        r.defines.length = defines.length;
        foreach (i, d; defines)
        {
            r.defines[i] = d.dup;
        }
        r.conditionUndef = conditionUndef;
        r.conditionUnknown = conditionUnknown;
        r.locked = locked;
        return r;
    }
}

class DefineSets
{
    DefineSet[string] defineSets;
    LogicSystem logicSystem;
    string[immutable(Formula)*] aliasMap;

    this(LogicSystem logicSystem)
    {
        this.logicSystem = logicSystem;
    }

    protected DefineSet getDefaultDefineSet(string def)
    {
        return null;
    }

    final DefineSet getDefineSetOrNull(string def)
    {
        if (def !in defineSets)
        {
            DefineSet r = getDefaultDefineSet(def);
            if (r !is null)
                defineSets[def] = r;
            return r;
        }
        return defineSets[def];
    }

    final DefineSet getDefineSet(string def)
    {
        if (def !in defineSets)
        {
            defineSets[def] = getDefaultDefineSet(def);
            if (defineSets[def] is null)
                defineSets[def] = new DefineSet(logicSystem, def);
        }
        return defineSets[def];
    }

    DefineSets dup()
    {
        DefineSets r = new DefineSets(logicSystem);
        foreach (n, d; defineSets)
        {
            r.defineSets[n] = d.dup(logicSystem);
        }
        return r;
    }

    void realizeAllDefines()
    {
    }
}

class InitialDefineSets : DefineSets
{
    struct UndefRegex
    {
        string def;
        Regex!char regex;
    }

    UndefRegex[] undefRegexes;
    string combinedUndefRegex;
    Regex!char undefRegex;
    bool undefRegexDirty = true;
    bool[string] undefRegexUsed;

    this(LogicSystem logicSystem)
    {
        super(logicSystem);

        undefRegexUsed[""] = true;
    }

    bool isUndefRegex(string def)
    {
        if (combinedUndefRegex.length == 0)
            return false;
        if (undefRegexDirty)
        {
            undefRegex = regex("^(?:" ~ combinedUndefRegex ~ ")$");
            undefRegexDirty = false;
        }
        if (!matchFirst(def, undefRegex).empty)
        {
            foreach (ref u; undefRegexes)
            {
                if (!matchFirst(def, u.regex).empty)
                {
                    undefRegexUsed[u.def] = true;
                }
            }
            return true;
        }
        return false;
    }

    protected override DefineSet getDefaultDefineSet(string def)
    {
        if (isUndefRegex(def))
        {
            DefineSet ret = new DefineSet(logicSystem, def);
            ret.conditionUnknown = logicSystem.false_;
            ret.conditionUndef = logicSystem.true_;
            return ret;
        }
        return null;
    }

    override InitialDefineSets dup()
    {
        InitialDefineSets r = new InitialDefineSets(logicSystem);
        r.combinedUndefRegex = combinedUndefRegex;
        r.undefRegexUsed = undefRegexUsed;
        foreach (n, d; defineSets)
        {
            r.defineSets[n] = d.dup(logicSystem);
        }
        return r;
    }

    void addUndefRegex(string def)
    {
        Regex!char tmpRegex = regex("^(?:" ~ def ~ ")$");
        undefRegexes ~= UndefRegex(def, tmpRegex);
        if (combinedUndefRegex.length)
            combinedUndefRegex ~= "|";
        combinedUndefRegex ~= def;
        undefRegexDirty = true;

        if (def !in undefRegexUsed)
            undefRegexUsed[def] = false;

        foreach (n, d; defineSets)
        {
            if (!matchFirst(n, tmpRegex).empty)
            {
                d.updateUndef(logicSystem, logicSystem.true_);
            }
        }
    }
}

immutable(Formula)* definesFormula(DefineSets defineSets)
{
    with (defineSets.logicSystem)
    {
        immutable(Formula)* r = true_;
        foreach (name, d; defineSets.defineSets)
        {
            r = and(r, or(d.conditionUndef, literal(text("defined(", name, ")"))));
        }
        return r;
    }
}

immutable(Formula)* replaceDefines(immutable(Formula)* f, DefineSets defineSets,
        immutable(Formula)*[Tree] defineConditions, immutable(Formula)*[string] unknownConditions,
        immutable(Formula)*[string] undefConditions)
{
    LogicSystem logicSystem = defineSets.logicSystem;
    return replaceAll!((f2) {
        if (f2.isSimple && f2.data.name.startsWith("defined("))
        {
            string name = f2.data.name["defined(".length .. $ - 1];
            auto d = defineSets.getDefineSet(name);
            d.used = true;

            immutable(Formula)* f4;
            if (f2.type == LogicSystem.FormulaType.literal)
            {
                f4 = d.conditionUndef.negated;
            }
            else
            {
                f4 = d.conditionUndef;
            }

            auto r = f4;
            return r;
        }
        else
            return f2;
    })(logicSystem, f);
}

ulong parseIntLiteral(string s)
{
    if (s == "0")
        return 0;
    else if (s.startsWith("0x"))
    {
        s = s[2 .. $];
        return parse!ulong(s, 16);
    }
    else if (s.startsWith("0"))
    {
        s = s[1 .. $];
        return parse!ulong(s, 8);
    }
    else
    {
        return parse!ulong(s, 10);
    }
}

enum StringOrNumType
{
    str,
    signed,
    unsigned
}

struct StringOrNum
{
    string s;
    StringOrNumType type;
    long n;
    bool isNumber()
    {
        return type == StringOrNumType.signed || type == StringOrNumType.unsigned;
    }
}

StringOrNum expressionToString(ParserWrapper)(Tree tree,
        ref IteratePPVersions ppVersion, Context!(ParserWrapper) context)
{
    assert(ppVersion.condition !is ppVersion.logicSystem.false_);
    if (tree.nodeType == NodeType.token)
    {
        if (tree.content.startsWith("@#defined"))
        {
            string name = tree.content["@#defined".length .. $];
            while (name.startsWith("(") && name.endsWith(")"))
                name = name[1 .. $ - 1];

            auto d = context.defineSets.getDefineSet(name);
            d.used = true;

            StringOrNum[] possibleResults;
            immutable(Formula)*[] conditions;

            with (ppVersion.logicSystem)
            {
                auto conditionDefined = or(d.conditionDefined(ppVersion.logicSystem),
                        d.conditionUnknown);
                if (and(ppVersion.condition, conditionDefined) !is false_)
                {
                    possibleResults ~= StringOrNum("1", StringOrNumType.signed, 1);
                    conditions ~= conditionDefined;
                }
                if (and(ppVersion.condition, d.conditionUndef) !is false_)
                {
                    possibleResults ~= StringOrNum("0", StringOrNumType.signed, 0);
                    conditions ~= d.conditionUndef;
                }

                if (possibleResults.length == 0)
                {
                    ppVersion.condition = false_;
                    return StringOrNum("defined(" ~ name ~ ")");
                }
                auto selected = ppVersion.combination.next(cast(uint) possibleResults.length);
                ppVersion.condition = and(ppVersion.condition, conditions[selected]);

                return possibleResults[selected];
            }
        }
        else
            return StringOrNum(tree.content);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"Literal")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType.among(NodeType.token, NodeType.array),
                text(tree, " ", tree.childs[0].nodeType));
        string s;
        if (tree.childs[0].nodeType == NodeType.token)
            s = tree.childs[0].content;
        else
        {
            foreach (part; tree.childs[0].childs)
            {
                assert(part.nodeType == NodeType.token);
                s ~= part.content;
            }
        }
        try
        {
            StringOrNumType type = StringOrNumType.signed;
            while (s.length && s[$ - 1].among('L', 'l', 'u', 'U'))
            {
                if (s[$ - 1] == 'u' || s[$ - 1] == 'U')
                    type = StringOrNumType.unsigned;
                s = s[0 .. $ - 1];
            }

            ulong l = parseIntLiteral(s);
            if (l >= 0x8000_0000_0000_0000LU)
                type = StringOrNumType.unsigned;
            return StringOrNum(s, type, l);
        }
        catch (ConvException)
        {
        }
        return StringOrNum(s);
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("AdditiveExpression",
            "MultiplicativeExpression", "InclusiveOrExpression",
            "AndExpression", "ExclusiveOrExpression"))
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].nodeType == NodeType.token);
        auto lhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        string op = tree.childs[1].content;
        auto rhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        if (lhs.isNumber && rhs.isNumber)
        {
            static foreach (op2; ["-", "+", "*", "/", "%", "|", "&", "^"])
                if (op == op2)
                {
                    if (op2 == "/" && rhs.n == 0)
                    {
                        throw new Exception("division by zero in condition ",
                                locationStr(tree.start));
                    }
                    if (lhs.type == StringOrNumType.unsigned || rhs.type == StringOrNumType.unsigned)
                    {
                        ulong lhsN = cast(ulong) lhs.n;
                        ulong rhsN = cast(ulong) rhs.n;
                        mixin("ulong r = lhsN " ~ op2 ~ " rhsN;");
                        return StringOrNum(text(r), (lhs.type == StringOrNumType.unsigned
                                || rhs.type == StringOrNumType.unsigned) ? StringOrNumType.unsigned
                                : StringOrNumType.signed, r);
                    }
                    else
                    {
                        mixin("long r = lhs.n " ~ op2 ~ " rhs.n;");
                        return StringOrNum(text(r), (lhs.type == StringOrNumType.unsigned
                                || rhs.type == StringOrNumType.unsigned) ? StringOrNumType.unsigned
                                : StringOrNumType.signed, r);
                    }
                }
            assert(false, op);
        }
        else if (lhs.isNumber && lhs.n == 0)
        {
            return rhs;
        }
        else if (rhs.isNumber && rhs.n == 0)
        {
            return lhs;
        }
        else
            return StringOrNum(lhs.s ~ op ~ rhs.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ShiftExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].nodeType == NodeType.token);
        auto lhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        string op = tree.childs[1].content;
        auto rhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        if (lhs.isNumber && rhs.isNumber)
        {
            static foreach (op2; ["<<", ">>"])
                if (op == op2)
                {
                    mixin("long r = lhs.n " ~ op2 ~ " rhs.n;");
                    return StringOrNum(text(r), lhs.type, r);
                }
            assert(false);
        }
        else if (op.among("+", "-") && lhs.isNumber && lhs.n == 0)
        {
            return rhs;
        }
        else if (op.among("+", "-") && rhs.isNumber && rhs.n == 0)
        {
            return lhs;
        }
        else
            return StringOrNum(lhs.s ~ op ~ rhs.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"RelationalExpression"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EqualityExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].nodeType == NodeType.token);
        auto lhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        string op = tree.childs[1].content;
        auto rhs = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        if (lhs.isNumber && rhs.isNumber)
        {
            int r = -1;
            static foreach (op2; ["<", ">", ">=", "<=", "==", "!="])
                if (op == op2)
                {
                    if (lhs.type == StringOrNumType.unsigned || rhs.type == StringOrNumType.unsigned)
                        mixin("r = lhs.n " ~ op2 ~ " cast(ulong)rhs.n;");
                    else
                        mixin("r = lhs.n " ~ op2 ~ " rhs.n;");
                }
            if (r >= 0)
                return StringOrNum(text(r), StringOrNumType.signed, r);
            else
                return StringOrNum(lhs.s ~ op ~ rhs.s);
        }
        else
            return StringOrNum(lhs.s ~ op ~ rhs.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PrimaryExpression"
            && tree.childs[0].content == "(")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[2].content == ")");
        auto inner = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[1],
                ppVersion, context);
        if (inner.isNumber)
            return inner;
        else
            return StringOrNum("(" ~ inner.s ~ ")");
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ConditionalExpression")
    {
        assert(tree.childs.length == 5);
        assert(tree.childs[1].content == "?");
        assert(tree.childs[3].content == ":");
        auto a = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        auto b = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        auto c = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[4],
                ppVersion, context);
        if (a.isNumber)
            return a.n ? b : c;
        return StringOrNum(a.s ~ " ? " ~ b.s ~ " : " ~ c.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"LogicalOrExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].content == "||");
        auto a = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        auto b = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        if (a.isNumber && b.isNumber)
            return StringOrNum(text(a.n || b.n), StringOrNumType.signed, a.n || b.n);
        if (a.isNumber)
        {
            if (a.n)
                return StringOrNum("1", StringOrNumType.signed, 1);
        }
        if (b.isNumber)
        {
            if (b.n)
                return StringOrNum("1", StringOrNumType.signed, 1);
        }
        return StringOrNum(a.s ~ " || " ~ b.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"LogicalAndExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].content == "&&");
        auto a = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
        auto b = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[2],
                ppVersion, context);
        if (a.isNumber && b.isNumber)
            return StringOrNum(text(a.n && b.n), StringOrNumType.signed, a.n && b.n);
        if (a.isNumber)
        {
            if (!a.n)
                return StringOrNum("0", StringOrNumType.signed, 0);
        }
        if (b.isNumber)
        {
            if (!b.n)
                return StringOrNum("0", StringOrNumType.signed, 0);
        }
        return StringOrNum(a.s ~ " && " ~ b.s);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].content.among("+", "-"))
    {
        assert(tree.childs.length == 2);
        auto inner = iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[1],
                ppVersion, context);
        if (inner.isNumber)
        {
            if (tree.childs[0].content == "-")
            {
                long r = -inner.n;
                return StringOrNum(text(r), StringOrNumType.signed, r);
            }
            if (tree.childs[0].content == "+")
                return inner;
        }
        return StringOrNum(tree.childs[0].content ~ " " ~ inner.s);
    }
    else if (tree.childs.length == 1)
    {
        return iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[0],
                ppVersion, context);
    }
    else
    {
        string r;
        foreach (c; tree.childs)
        {
            auto x = iteratePPVersions!(expressionToString!(ParserWrapper))(c, ppVersion, context);
            if (x.s.length)
            {
                r ~= x.s;
            }
        }
        return StringOrNum(r);
    }
}

StringOrNum expressionToStringNoParens(ParserWrapper)(Tree tree,
        ref IteratePPVersions ppVersion, Context!(ParserWrapper) context)
{
    assert(ppVersion.condition !is ppVersion.logicSystem.false_);
    if (tree.nodeType == NodeType.nonterminal
            && tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PrimaryExpression"
            && tree.childs[0].content == "(")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[2].content == ")");
        return iteratePPVersions!(expressionToString!(ParserWrapper))(tree.childs[1],
                ppVersion, context);
    }
    else
    {
        return expressionToString(tree, ppVersion, context);
    }
}

immutable(Formula)* evaluateExpression(ParserWrapper)(Tree tree,
        immutable(Formula)* contextCondition, Context!(ParserWrapper) context)
{
    if (contextCondition.isFalse)
        return contextCondition;
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        immutable(Formula)* r = context.logicSystem.false_;
        foreach (i, c; tree.childs)
        {
            auto cond = evaluateExpression!(ParserWrapper)(c, contextCondition, context);
            cond = context.logicSystem.and(cond, ctree.conditions[i]);
            r = context.logicSystem.or(r, cond);
        }
        return r;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"LogicalAndExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].content == "&&");
        return context.logicSystem.and(evaluateExpression!(ParserWrapper)(tree.childs[0],
                contextCondition, context), evaluateExpression!(ParserWrapper)(tree.childs[2],
                contextCondition, context));
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"LogicalOrExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].content == "||");
        return context.logicSystem.or(evaluateExpression!(ParserWrapper)(tree.childs[0],
                contextCondition, context), evaluateExpression!(ParserWrapper)(tree.childs[2],
                contextCondition, context));
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EqualityExpression"
            && tree.childs[0].nonterminalID == nonterminalIDFor!"MultiplicativeExpression"
            && tree.childs[0].childs[0].nonterminalID == nonterminalIDFor!"Literal"
            && tree.childs[0].childs[0].childs[0].content == "1"
            && tree.childs[0].childs[1].content == "/"
            && tree.childs[0].childs[2].nonterminalID == nonterminalIDFor!"NameIdentifier"
            && tree.childs[1].content == "=="
            && tree.childs[2].nonterminalID == nonterminalIDFor!"Literal"
            && tree.childs[2].childs[0].content == "1")
    {
        // Special case for QT_CONFIG
        Tree lhsTree = tree.childs[0].childs[2];

        immutable(Formula)* outCondition = context.logicSystem.false_;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    context.logicSystem, contextCondition);

            immutable(Formula)* c;

            auto lhs = iteratePPVersions!(expressionToStringNoParens!(ParserWrapper))(lhsTree,
                    ppVersion, context);
            if (lhs.isNumber)
            {
                if (1 / lhs.n == 1)
                    c = context.logicSystem.true_;
                else
                    c = context.logicSystem.false_;
            }
            else
                c = context.logicSystem.boundLiteral(lhs.s, "==", 1);

            with (context.logicSystem)
            {
                outCondition = simplify(distributeOrSimple(outCondition,
                        and(ppVersion.condition, c)));
            }
        }
        return outCondition;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"RelationalExpression"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EqualityExpression")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[1].nodeType == NodeType.token);
        Tree lhsTree = tree.childs[0];
        Tree rhsTree = tree.childs[2];

        immutable(Formula)* outCondition = context.logicSystem.false_;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    context.logicSystem, contextCondition);

            immutable(Formula)* c;

            auto lhs = iteratePPVersions!(expressionToStringNoParens!(ParserWrapper))(lhsTree,
                    ppVersion, context);
            string op = tree.childs[1].content;
            auto rhs = iteratePPVersions!(expressionToStringNoParens!(ParserWrapper))(rhsTree,
                    ppVersion, context);
            if (lhs.isNumber && rhs.isNumber)
            {
                // Same as expressionToString
                int r = -1;
                static foreach (op2; ["<", ">", ">=", "<=", "==", "!="])
                    if (op == op2)
                    {
                        if (lhs.type == StringOrNumType.unsigned
                                || rhs.type == StringOrNumType.unsigned)
                            mixin("r = lhs.n " ~ op2 ~ " cast(ulong)rhs.n;");
                        else
                            mixin("r = lhs.n " ~ op2 ~ " rhs.n;");
                    }
                if (r >= 0)
                {
                    if (r)
                        c = context.logicSystem.true_;
                    else
                        c = context.logicSystem.false_;
                }
                else
                    c = context.logicSystem.literal(lhs.s ~ op ~ rhs.s);
            }
            else if (lhs.isNumber)
            {
                c = context.logicSystem.boundLiteral(lhs.n, op, rhs.s);
            }
            else if (rhs.isNumber)
            {
                c = context.logicSystem.boundLiteral(lhs.s, op, rhs.n);
            }
            else
                c = context.logicSystem.literal(lhs.s ~ op ~ rhs.s);

            with (context.logicSystem)
            {
                outCondition = simplify(distributeOrSimple(outCondition,
                        and(ppVersion.condition, c)));
            }
        }
        return outCondition;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].content == "!")
    {
        assert(tree.childs.length == 2);
        return context.logicSystem.not(evaluateExpression!(ParserWrapper)(tree.childs[1],
                contextCondition, context));
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PrimaryExpression"
            && tree.childs[0].content == "(")
    {
        assert(tree.childs.length == 3);
        assert(tree.childs[2].content == ")");
        return evaluateExpression!(ParserWrapper)(tree.childs[1], contextCondition, context);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PrimaryExpression"
            && tree.childs.length == 1)
    {
        return evaluateExpression!(ParserWrapper)(tree.childs[0], contextCondition, context);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ConditionalExpression")
    {
        assert(tree.childs.length == 5);
        assert(tree.childs[1].content == "?");
        assert(tree.childs[3].content == ":");
        auto a = evaluateExpression!(ParserWrapper)(tree.childs[0], contextCondition, context);
        auto b = evaluateExpression!(ParserWrapper)(tree.childs[2], contextCondition, context);
        auto c = evaluateExpression!(ParserWrapper)(tree.childs[4], contextCondition, context);
        return context.logicSystem.or(context.logicSystem.and(a, b),
                context.logicSystem.and(a.negated, b));
    }

    immutable(Formula)* outCondition = context.logicSystem.false_;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination,
                context.logicSystem, contextCondition);

        auto x = iteratePPVersions!(expressionToStringNoParens!(ParserWrapper))(tree,
                ppVersion, context);
        immutable(Formula)* c;
        if (x.isNumber)
        {
            if (x.n)
                c = context.logicSystem.true_;
            else
                c = context.logicSystem.false_;
        }
        else
            c = context.logicSystem.literal(x.s);

        with (context.logicSystem)
        {
            outCondition = simplify(distributeOrSimple(outCondition, and(ppVersion.condition, c)));
        }
    }
    return outCondition;
}

Tree parsePPExpr(ParserWrapper)(Tree[] exprTokens, immutable(LocationContext)* locationContext,
        immutable(Formula)* condition, Context!(ParserWrapper) context)
{
    SingleParallelParser!(ParserWrapper) singleParser = new SingleParallelParser!(ParserWrapper)(
            context);
    singleParser.startParseExpr(false  /*isCPlusPlus*/ , null, &globalStringPool);

    ParallelParser!(ParserWrapper) parser = singleParser;

    Tree[] parsed = parseMacroContent(exprTokens, true);
    foreach (tokenNr, t; parsed)
    {
        bool isNextParen;
        if (tokenNr + 1 < parsed.length)
        {
            if (parsed[tokenNr + 1].childs[0].content == "(")
                isNextParen = true;
        }
        bool[string] macrosDone;

        processToken!(ParserWrapper)(reparentLocation(t.start, locationContext), t, context, condition,
                parser, isNextParen, null, Location.invalid, macrosDone, null, false);
    }

    parser.pushEnd(context.logicSystem.true_);

    parser = parser.tryMerge(condition, false, null);
    singleParser = cast(SingleParallelParser!(ParserWrapper)) parser;

    assert(singleParser !is null);
    parser = singleParser;

    Tree pt = singleParser.pushParser.getAcceptedExpression;

    return pt;
}

Tree parsePPExpr(ParserWrapper)(string expr, immutable(LocationContext)* locationContext,
        immutable(Formula)* condition, LogicSystem logicSystem, DefineSets defineSets)
{
    Context!(ParserWrapper) context = new Context!(ParserWrapper)(logicSystem, defineSets);
    context.locationContextMap = new LocationContextMap;
    context.insidePPExpression = true;

    Tree t = Tree(expr, SymbolID.max, ProductionID.max, NodeType.token, []);
    auto grammarInfo = getDummyGrammarInfo("Token");
    t.grammarInfo = grammarInfo;
    t.setStartEnd(LocationX(LocationN.init, locationContext),
            LocationX(LocationN.init, locationContext));
    Tree t2 = Tree("Token", grammarInfo.startNonterminalID,
            grammarInfo.startProductionID, NodeType.nonterminal, [t]);
    t2.grammarInfo = grammarInfo;
    t2.setStartEnd(LocationX(LocationN.init, locationContext),
            LocationX(LocationN.init, locationContext));

    return parsePPExpr!ParserWrapper([t2], locationContext, condition, context);
}

immutable(Formula)* exprToCondition(ParserWrapper)(Tree expr, immutable(LocationContext)* locationContext,
        immutable(Formula)* condition, LogicSystem logicSystem, DefineSets defineSets)
{
    Context!(ParserWrapper) context = new Context!(ParserWrapper)(logicSystem, defineSets);
    context.locationContextMap = new LocationContextMap;
    context.insidePPExpression = true;

    Tree pt;
    try
    {
        pt = parsePPExpr!ParserWrapper(expr.childs, locationContext, condition, context);
    }
    catch (Exception e)
    {
        stderr.writeln("location: ", locationStr(reparentLocation(expr.start, locationContext)));
        throw e;
    }

    immutable(Formula)* outCondition = logicSystem.false_;

    auto exprCondition = evaluateExpression!(ParserWrapper)(pt, condition, context);

    with (logicSystem)
    {
        outCondition = and(condition, exprCondition);
    }

    return outCondition;
}

void updateDefineSet(ParserWrapper)(DefineSets defineSets, immutable(Formula)* condition, Tree l)
{
    LogicSystem logicSystem = defineSets.logicSystem;
    if (l.nonterminalID == preprocNonterminalIDFor!"VarDefine")
    {
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).update(logicSystem, condition, false, l);
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
    {
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).update(logicSystem, condition, true, l);
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"Undef")
    {
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).updateUndef(logicSystem, condition);
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"RegexUndef")
    {
        assert(l.childs[1].content == "#");
        assert(l.childs[3].content == "regex_undef");

        string def = l.childs[5].content[1 .. $ - 1];

        InitialDefineSets initialDefineSets = cast(InitialDefineSets) defineSets;

        if (initialDefineSets is null || !condition.isTrue)
            throw new Exception("#regex_undef not allowed here");

        initialDefineSets.addUndefRegex(def);
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"Unknown")
    {
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).updateUnknown(logicSystem, condition);
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"LockDefine")
    {
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).locked = true;
    }
    else if (l.nonterminalID == preprocNonterminalIDFor!"AliasDefine")
    {
        /* #alias NAME EXPR
         * Equivalent to:
         * #undef NAME
         * #if EXPR
         * #define NAME EXPR
         * #endif
         */
        string def = l.childs[5].content;

        defineSets.getDefineSet(def).updateUndef(logicSystem, condition);

        immutable(Formula)* condition2 = exprToCondition!(ParserWrapper)(l.childs[7],
                l.location.context, defineSets.logicSystem.true_,
                defineSets.logicSystem, defineSets);

        if (!condition2.isAnyLiteralFormula)
            throw new Exception(text("alias with non literal condition ", l,
                    " ", condition2.toString));

        Tree[] childs;
        childs ~= Tree.init;
        childs ~= Tree.init;
        childs ~= Tree.init;
        childs ~= Tree.init;
        childs ~= Tree.init;
        childs ~= Tree(def, SymbolID.max, ProductionID.max, NodeType.token, []);
        childs ~= Tree(" ", SymbolID.max, ProductionID.max, NodeType.token, []);
        Tree content = Tree("1", SymbolID.max, ProductionID.max, NodeType.token, []);
        content.setStartEnd(l.start, l.end);
        auto grammarInfo = getDummyGrammarInfo("Token");
        Tree token = Tree("Token", grammarInfo.startNonterminalID,
                grammarInfo.startProductionID, NodeType.nonterminal, [content]);
        token.grammarInfo = grammarInfo;
        token.setStartEnd(l.start, l.end);
        childs ~= Tree("[]", SymbolID.max, ProductionID.max, NodeType.array, [token]);
        grammarInfo = getDummyGrammarInfo("VarDefine");
        Tree definition = Tree("VarDefine", grammarInfo.startNonterminalID,
                grammarInfo.startProductionID, NodeType.nonterminal, childs);
        definition.grammarInfo = grammarInfo;
        definition.setStartEnd(l.start, l.end);

        defineSets.getDefineSet(def).update(logicSystem,
                defineSets.logicSystem.and(condition, condition2), false, definition);

        if (condition2 in defineSets.aliasMap)
        {
            enforce(defineSets.aliasMap[condition2] == def);
        }
        else
            defineSets.aliasMap[condition2] = def;
    }
    else
        assert(false);
}

immutable(Formula)* preprocIfToCondition(ParserWrapper)(Tree x, immutable(LocationContext)* locationContext,
        immutable(Formula)* condition, LogicSystem logicSystem, DefineSets defineSets)
{
    with (logicSystem)
    {
        if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIfDef")
            return replaceDefines(literal(text("defined(",
                    x.childs[0].childs[$ - 1].childs[0].content, ")")),
                    defineSets, null, null, null);
        else if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIfNDef")
            return replaceDefines(notLiteral(text("defined(",
                    x.childs[0].childs[$ - 1].childs[0].content, ")")),
                    defineSets, null, null, null);
        else if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIf")
            return exprToCondition!(ParserWrapper)(x.childs[0].childs[$ - 1],
                    locationContext, condition, logicSystem, defineSets);
        else if (x.childs[0].nonterminalID == preprocNonterminalIDFor!"PPElif")
            return exprToCondition!(ParserWrapper)(x.childs[0].childs[$ - 1],
                    locationContext, condition, logicSystem, defineSets);
        else
            return literal("NOT_IMPLEMENTED_CONDITION");
    }
}

void collectAllDefines(ParserWrapper)(Tree tree, DefineSets defineSets, ref bool[string] hasUndef)
{
    if (!tree.isValid)
        return;
    if (tree.nonterminalID == preprocNonterminalIDFor!"Undef")
    {
        hasUndef[tree.childs[5].content] = true;
    }
    if (tree.nonterminalID == preprocNonterminalIDFor!"VarDefine"
            || tree.nonterminalID == preprocNonterminalIDFor!"FuncDefine"
            || tree.nonterminalID == preprocNonterminalIDFor!"Undef")
    {
        updateDefineSet!ParserWrapper(defineSets, defineSets.logicSystem.true_, tree);
    }
    else
    {
        foreach (child; tree.childs)
            collectAllDefines!ParserWrapper(child, defineSets, hasUndef);
    }
}

immutable(Formula)* removeLocationInstanceConditions(immutable(Formula)* f,
        LogicSystem logicSystem, MergedFile*[RealFilename] mergedFileByName)
{
    immutable(Formula)*[string] chosen;
    immutable(Formula)* result = logicSystem.false_;
    foreach (combination; iterateCombinations())
    {
        chosen.clear();
        immutable(Formula)* f3 = replaceAll!((f2) {
            if (f2.isAnyLiteralFormula && f2.data.name.startsWith("@includetu:"))
            {
                string name = f2.data.name["@includetu:".length .. $];

                immutable(Formula)* last = logicSystem.true_;
                if (name in chosen)
                {
                    last = chosen[name];
                    if (logicSystem.and(last, f2).isFalse)
                        return logicSystem.false_;
                    if (logicSystem.and(last, f2.negated).isFalse)
                        return logicSystem.true_;
                }
                if (combination.next(2) == 0)
                {
                    chosen[name] = logicSystem.and(last, f2);
                    return logicSystem.true_;
                }
                else
                {
                    chosen[name] = logicSystem.and(last, f2.negated);
                    return logicSystem.false_;
                }
            }
            else if (f2.isAnyLiteralFormula && f2.data.name.startsWith("@includex:"))
            {
                string name = f2.data.name["@includex:".length .. $];

                immutable(Formula)* last = logicSystem.true_;
                if (name in chosen)
                {
                    last = chosen[name];
                    if (logicSystem.and(last, f2).isFalse)
                        return logicSystem.false_;
                    if (logicSystem.and(last, f2.negated).isFalse)
                        return logicSystem.true_;
                }
                if (combination.next(2) == 0)
                {
                    chosen[name] = logicSystem.and(last, f2);
                    return logicSystem.true_;
                }
                else
                {
                    chosen[name] = logicSystem.and(last, f2.negated);
                    return logicSystem.false_;
                }
            }
            else
                return f2;
        })(logicSystem, f);

        foreach (name, c; chosen)
        {
            auto mergedFile = mergedFileByName[RealFilename(name)];
            immutable(Formula)* f4 = logicSystem.false_;
            foreach (instance; mergedFile.instances)
            {
                if (instance.instanceCondition is null)
                    continue;
                if (!logicSystem.and(c, instance.instanceCondition).isFalse)
                    f4 = logicSystem.or(f4, instance.instanceConditionUsed);
            }
            f3 = logicSystem.and(f3, f4);
        }

        result = logicSystem.or(result, f3);
    }
    return result;
}
