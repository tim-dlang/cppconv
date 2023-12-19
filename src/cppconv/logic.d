
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.logic;
import cppconv.utils;
import dparsergen.core.utils;
import std.algorithm;
import std.conv;
import std.meta;
import std.range;
import std.stdio;
import std.typecons;

size_t[2] impliesSimpleCacheResults;

enum ADD_SOURCE_INFO = false;

bool isAnyLiteralFormula(T)(T.FormulaType type)
{
    return type != T.FormulaType.and && type != T.FormulaType.or;
}

bool isAnyLiteralFormula(T)(const FormulaX!T* formula)
{
    return isAnyLiteralFormula(formula.type);
}

T.FormulaType negateType(T)(T.FormulaType type)
{
    return cast(T.FormulaType)(type ^ 1);
}

struct FormulaX(T)
{
    alias FormulaType = T.FormulaType;
    //@disable this();

    this(FormulaType type) immutable
    {
        this.type = type;
    }

    FormulaType type;

    immutable(FormulaX*[]) subFormulas_() const
    {
        return doubleFormula.subFormulas_;
    }

    ref const(T) data() const
    {
        return doubleFormula.data;
    }

    immutable(DoubleFormulaX!T)* doubleFormula() immutable
    {
        if (type & 1)
            return cast(immutable(DoubleFormulaX!T)*)(
                    (cast(void*)&this) - DoubleFormulaX!T.init.negated.offsetof);
        else
            return cast(immutable(DoubleFormulaX!T)*)(
                    (cast(void*)&this) - DoubleFormulaX!T.init.normal.offsetof);
    }

    const(DoubleFormulaX!T)* doubleFormula() const
    {
        if (type & 1)
            return cast(const(DoubleFormulaX!T)*)(
                    (cast(void*)&this) - DoubleFormulaX!T.init.negated.offsetof);
        else
            return cast(const(DoubleFormulaX!T)*)(
                    (cast(void*)&this) - DoubleFormulaX!T.init.normal.offsetof);
    }

    immutable(FormulaX)* negated() immutable
    {
        auto d = doubleFormula;
        if (type & 1)
            return &d.normal;
        else
            return &d.negated;
    }

    const(FormulaX)* negated() const
    {
        auto d = doubleFormula;
        if (type & 1)
            return &d.normal;
        else
            return &d.negated;
    }

    static struct SubFormulasRange(F)
    {
        const(F*)[] data;
        bool negate;
        bool empty() const
        {
            return data.length > 0;
        }

        F* front() const
        {
            auto r = data[0];
            if (negate)
                return r.negated;
            return r;
        }

        void popFront()
        {
            data = data[1 .. $];
        }

        size_t length() const
        {
            return data.length;
        }

        F* opIndex(size_t k) const
        {
            auto r = data[k];
            if (negate)
                return r.negated;
            return r;
        }

        int opApply(scope int delegate(size_t, F*) dg)
        {
            if (negate)
            {
                foreach (k; 0 .. data.length)
                {
                    int r = dg(k, data[k].negated);
                    if (r)
                        return r;
                }
            }
            else
            {
                foreach (k; 0 .. data.length)
                {
                    int r = dg(k, data[k]);
                    if (r)
                        return r;
                }
            }
            return 0;
        }

        int opApply(scope int delegate(F*) dg)
        {
            if (negate)
            {
                foreach (k; 0 .. length)
                {
                    int r = dg(data[k].negated);
                    if (r)
                        return r;
                }
            }
            else
            {
                foreach (k; 0 .. length)
                {
                    int r = dg(data[k]);
                    if (r)
                        return r;
                }
            }
            return 0;
        }
    }

    SubFormulasRange!(immutable(FormulaX)) subFormulas() immutable
    {
        if (type == FormulaType.and)
            return SubFormulasRange!(immutable(FormulaX))(this.subFormulas_, false);
        else if (type == FormulaType.or)
            return SubFormulasRange!(immutable(FormulaX))(this.negated.subFormulas_, true);
        else
            assert(false);
    }

    SubFormulasRange!(const(FormulaX)) subFormulas() const
    {
        if (type == FormulaType.and)
            return SubFormulasRange!(const(FormulaX))(this.subFormulas_, false);
        else if (type == FormulaType.or)
            return SubFormulasRange!(const(FormulaX))(this.negated.subFormulas_, true);
        else
            assert(false);
    }

    size_t subFormulasLength() const
    {
        if (type == FormulaType.and)
            return subFormulas_.length;
        else if (type == FormulaType.or)
            return negated.subFormulas_.length;
        else
            assert(false);
    }

    void toString(O)(ref O outRange) const
    {
        assert((cast(ubyte) type) != 0xff);
        if (type == FormulaType.and)
        {
            if (subFormulasLength == 0)
            {
                outRange.put("⊤");
                return;
            }
            outRange.put("(");
            foreach (i, f; subFormulas)
            {
                if (i)
                    outRange.put(" ∧ ");
                f.toString(outRange);
            }
            outRange.put(")");
        }
        else if (type == FormulaType.or)
        {
            if (subFormulasLength == 0)
            {
                outRange.put("⊥");
                return;
            }
            outRange.put("(");
            foreach (i, f; subFormulas)
            {
                if (i)
                    outRange.put(" ∨ ");
                f.toString(outRange);
            }
            outRange.put(")");
        }
        else
            data.toString(outRange, type);
    }

    string toString() const
    {
        Appender!string app;
        toString(app);
        return app.data;
    }

    int opCmp(ref const FormulaX rhs) const
    {
        if (isAnyLiteralFormula(type) && !isAnyLiteralFormula(&rhs))
            return -1;
        if (!isAnyLiteralFormula(type) && isAnyLiteralFormula(&rhs))
            return 1;
        if (isAnyLiteralFormula(type))
        {
            if (data < rhs.data)
                return -1;
            if (data > rhs.data)
                return 1;
            if (type == rhs.type)
                return 0;
            if (type < rhs.type)
                return -1;
            else
                return 1;
        }
        else
        {
            if (type != rhs.type)
            {
                if (type == FormulaType.and)
                    return -1;
                else
                    return 1;
            }
            for (size_t i = 0; i < subFormulasLength && i < rhs.subFormulasLength;
                    i++)
            {
                int r = subFormulas[i].opCmp(*rhs.subFormulas[i]);
                if (r != 0)
                    return r;
            }
            if (subFormulasLength < rhs.subFormulasLength)
                return -1;
            if (subFormulasLength > rhs.subFormulasLength)
                return 1;
            return 0;
        }
    }

    bool isFalse() const
    {
        return type == FormulaType.or && subFormulasLength == 0;
    }

    bool isTrue() const
    {
        return type == FormulaType.and && subFormulasLength == 0;
    }
}

struct DoubleFormulaX(T)
{
    alias FormulaType = T.FormulaType;
    FormulaX!T normal;
    FormulaX!T negated;

    union
    {
        immutable FormulaX!T*[] subFormulas_;
        T data;
    }

    //@disable this();

    this(FormulaType type, T data) immutable
    in
    {
        assert(type.isAnyLiteralFormula);
    }
    do
    {
        this.data = data;
        normal = immutable(FormulaX!T)(type);
        negated = immutable(FormulaX!T)(negateType(type));
    }

    this(FormulaType type, immutable FormulaX!T*[] subFormulas) immutable
    in
    {
        assert(type == FormulaType.and);
    }
    do
    {
        this.subFormulas_ = subFormulas;
        normal = immutable(FormulaX!T)(FormulaType.and);
        negated = immutable(FormulaX!T)(FormulaType.or);
    }
}

bool evaluate(alias F, T)(immutable FormulaX!T* f)
{
    alias FormulaType = T.FormulaType;
    switch (f.type)
    {
    case FormulaType.and:
        foreach (s; f.subFormulas)
            if (!evaluate!(F, T)(s))
                return false;
        return true;
    case FormulaType.or:
        foreach (s; f.subFormulas)
            if (evaluate!(F, T)(s))
                return true;
        return false;
    default:
        if (f.type & 1)
            return !F(f.data, cast(FormulaType)(f.type & ~1));
        else
            return F(f.data, f.type);
    }
}

bool boundEvaluateImpl(alias F)(const BoundLiteral data, BoundLiteral.FormulaType type)
{
    auto val = F(data.name);
    if (type == BoundLiteral.FormulaType.greaterEq)
        return val >= data.number;
    else if (type == BoundLiteral.FormulaType.literal)
        return val != data.number;
    else
        assert(false);
}

bool boundEvaluate(alias F)(immutable FormulaX!BoundLiteral* f)
{
    return evaluate!(boundEvaluateImpl!F, BoundLiteral)(f);
}

void checkFormula(T)(immutable FormulaX!T* f, lazy string msg = "")
{
    if (f.isAnyLiteralFormula)
        return;
    foreach (s; f.subFormulas)
    {
        assert(s.type != f.type, msg);
        checkFormula(s, msg);
    }
}

enum ReplaceAllBehaviour
{
    none,
    preferAnd,
    preferOr
}

immutable(FormulaX!T*) replaceAll(alias F, T)(LogicSystemX!T this_,
        immutable FormulaX!T* f, ReplaceAllBehaviour behaviour = ReplaceAllBehaviour.none)
{
    alias FormulaType = T.FormulaType;
    immutable(FormulaX!T*)[] subFormulas;
    switch (f.type)
    {
    case FormulaType.and:
        foreach (s; f.subFormulas_)
        {
            auto part = replaceAll!F(this_, s, behaviour);
            if (part.isFalse)
                return this_.false_;
            subFormulas ~= part;
        }
        if (behaviour == ReplaceAllBehaviour.preferOr && subFormulas.length >= 2)
        {
            immutable(FormulaX!T)* tmp = subFormulas[0];
            foreach (i; 1 .. subFormulas.length)
                tmp = this_.distributeAndSimple(tmp, subFormulas[i] /*, filename, line*/ );
            return F(tmp);
        }
        else
            return F(this_.and(subFormulas));
    case FormulaType.or:
        foreach (s_; f.subFormulas_)
        {
            auto s = s_.negated;
            auto part = replaceAll!F(this_, s, behaviour);
            if (part.isTrue)
                return this_.true_;
            subFormulas ~= part;
        }
        if (behaviour == ReplaceAllBehaviour.preferAnd && subFormulas.length >= 2)
        {
            immutable(FormulaX!T)* tmp = subFormulas[0];
            foreach (i; 1 .. subFormulas.length)
                tmp = this_.distributeOrSimple(tmp, subFormulas[i] /*, filename, line*/ );
            return F(tmp);
        }
        else
            return F(this_.or(subFormulas));
    default:
        return F(f);
    }
}

class LogicSystemX(T)
{
    alias FormulaType = T.FormulaType;
    alias Formula = FormulaX!T;
    alias DoubleFormula = DoubleFormulaX!T;
    immutable Formula* true_;
    immutable Formula* false_;
    this()
    {
        true_ = and([]);
        false_ = or([]);
    }

    this(LogicSystemX orig)
    {
        true_ = orig.true_;
        false_ = orig.false_;
        literalFormulas = orig.literalFormulas.dup;
        andFormulas = orig.andFormulas.dup;
    }

    struct LiteralKey
    {
        FormulaType type;
        T data;
    }

    immutable(Formula)*[LiteralKey] literalFormulas;
    immutable(Formula)*[immutable(Formula*[])] andFormulas;
    SimpleArrayAllocator2!(immutable(DoubleFormula)) formulaAllocator;
    SimpleArrayAllocator2!(immutable(Formula*)) formulaArrayAllocator;

    immutable(Formula*) formula(FormulaType type, T data)
    in
    {
        assert(isAnyLiteralFormula(type));
    }
    out (r)
    {
        checkFormula(r);
    }
    do
    {
        if (!(type & 1))
        {
            auto cacheEntry = LiteralKey(type, data) in literalFormulas;
            immutable(Formula)* r;
            if (cacheEntry)
                r = *cacheEntry;
            else
            {
                auto d = formulaAllocator.allocateOne(immutable(DoubleFormula)(type, data)).ptr;
                r = &d.normal;
                literalFormulas[LiteralKey(type, data)] = r;
            }
            return r;
        }
        else
        {
            return formula(negateType(type), data).negated;
        }
    }

    immutable(Formula*) formula(FormulaType type, const(immutable(Formula)*)[] subFormulas)
    in
    {
        assert(!isAnyLiteralFormula(type));
    }
    do
    {
        static Appender!(immutable(Formula)*[]) subFormulas2;
        static bool[immutable(Formula)*] done;
        scope (exit)
        {
            subFormulas2.clear();
            done.clear();
        }
        void addSubFormulas(immutable(Formula)* f)
        {
            if (f.type == type)
                foreach (f2; f.subFormulas)
                    addSubFormulas(f2);
            else
            {
                if (type == FormulaType.or)
                    f = f.negated;
                if (f !in done)
                {
                    done[f] = true;
                    subFormulas2.put(f);
                }
            }
        }

        foreach (f; subFormulas)
            addSubFormulas(f);

        if (type == FormulaType.or)
        {
            return formulaImpl(FormulaType.and, subFormulas2.data, done).negated;
        }
        else
            return formulaImpl(type, subFormulas2.data, done);
    }

    immutable(Formula*) formula(P...)(FormulaType type,
            const(immutable(Formula)*) subFormula1, P subFormulas)
    in
    {
        assert(!isAnyLiteralFormula(type));
    }
    do
    {
        static Appender!(immutable(Formula)*[]) subFormulas2;
        static bool[immutable(Formula)*] done;
        scope (exit)
        {
            subFormulas2.clear();
            done.clear();
        }
        void addSubFormulas(immutable(Formula)* f)
        {
            if (f.type == type)
                foreach (f2; f.subFormulas)
                    addSubFormulas(f2);
            else
            {
                if (type == FormulaType.or)
                    f = f.negated;
                if (f !in done)
                {
                    done[f] = true;
                    subFormulas2.put(f);
                }
            }
        }

        addSubFormulas(subFormula1);
        foreach (f; subFormulas)
            addSubFormulas(f);

        if (type == FormulaType.or)
        {
            return formulaImpl(FormulaType.and, subFormulas2.data, done).negated;
        }
        else
            return formulaImpl(type, subFormulas2.data, done);
    }

    immutable(Formula*) filterDone(immutable(Formula*) f, const(immutable(Formula)*)[] done)
    {
        if (f.isAnyLiteralFormula)
            return f;

        static Appender!(immutable(Formula)*[]) innerSubFormulas;
        size_t sizeBegin = innerSubFormulas.data.length;
        scope (exit)
            innerSubFormulas.shrinkTo(sizeBegin);

        if (f.type == FormulaType.or)
        {
            bool changed;
            foreach (f2_; f.subFormulas_)
            {
                auto f2 = f2_.negated;
                bool foundNegated;
                foreach (d; done)
                {
                    if (d is null)
                        continue;
                    if (impliesSimple(d, f2))
                        return true_;
                    if (impliesSimple(d, f2.negated))
                        foundNegated = true;
                }
                if (foundNegated)
                {
                    changed = true;
                    continue;
                }
                assert(f2.type != FormulaType.or);
                auto f3 = filterDone(f2, done);
                if (f3 !is f2)
                {
                    changed = true;
                    foundNegated = false;
                    foreach (d; done)
                    {
                        if (d is null)
                            continue;
                        if (impliesSimple(d, f3))
                            return true_;
                        if (impliesSimple(d, f3.negated))
                            foundNegated = true;
                    }
                    if (foundNegated)
                        continue;
                }
                innerSubFormulas.put(f3);
            }
            if (innerSubFormulas.data.length == sizeBegin)
                return false_;
            if (!changed)
            {
                return f;
            }
            else
            {
                auto x = formula(FormulaType.or, innerSubFormulas.data[sizeBegin .. $]);
                return x;
            }
        }
        else if (f.type == FormulaType.and)
        {
            bool changed;
            foreach (f2; f.subFormulas_)
            {
                bool found;
                foreach (d; done)
                {
                    if (d is null)
                        continue;
                    if (impliesSimple(d, f2.negated))
                        return false_;
                    if (impliesSimple(d, f2))
                        found = true;
                }
                if (found)
                {
                    changed = true;
                    continue;
                }
                assert(f2.type != FormulaType.and);
                auto f3 = filterDone(f2, done);
                if (f3 !is f2)
                {
                    changed = true;
                    found = false;
                    foreach (d; done)
                    {
                        if (d is null)
                            continue;
                        if (impliesSimple(d, f3.negated))
                            return false_;
                        if (impliesSimple(d, f3))
                            found = true;
                    }
                    if (found)
                        continue;
                }
                innerSubFormulas.put(f3);
            }
            if (innerSubFormulas.data.length == sizeBegin)
                return true_;
            if (!changed)
            {
                return f;
            }
            else
            {
                auto x = formula(FormulaType.and, innerSubFormulas.data[sizeBegin .. $]);
                return x;
            }
        }
        else
            assert(false);
    }

    immutable(Formula*) formulaImpl(FormulaType type, immutable(Formula)*[] subFormulas2,
            bool[immutable(Formula)*] done)
    {
        assert(type == FormulaType.and);

        for (size_t i = 0; i < subFormulas2.length; i++)
        {
            if (!subFormulas2[i].isAnyLiteralFormula)
                continue;
            for (size_t k = i + 1; k < subFormulas2.length;)
            {
                if (subFormulas2[k].isAnyLiteralFormula
                        && subFormulas2[i].data.mergeKey == subFormulas2[k].data.mergeKey)
                {
                    auto f1 = subFormulas2[i];
                    auto f2 = subFormulas2[k];

                    auto r = mergeAndImpl(f1, f2);
                    if (r !is null)
                    {
                        subFormulas2[i] = r;
                        subFormulas2[k] = subFormulas2[$ - 1];
                        subFormulas2.length--;
                        k = i + 1;
                        continue; // no k++;
                    }
                }
                k++;
            }
        }

        foreach (f; subFormulas2)
        {
            if (f is false_)
                return false_;
            if (f.negated in done)
            {
                return false_;
            }
        }

        if (subFormulas2.length == 1)
        {
            return subFormulas2[0];
        }

        subFormulas2.sort!"a.opCmp(*b) < 0"();
        immutable(Formula*)[] subFormulas3 = formulaArrayAllocator.allocate(subFormulas2);

        auto cacheEntry = subFormulas3 in andFormulas;
        immutable(Formula)* r;
        if (cacheEntry)
            r = *cacheEntry;
        else
        {
            auto d = formulaAllocator.allocateOne(immutable(DoubleFormula)(FormulaType.and,
                    subFormulas3)).ptr;
            r = &d.normal;
            andFormulas[subFormulas3] = r;
        }

        return r;
    }

    immutable(Formula*) and(const(immutable(Formula)*)[] subFormulas)
    {
        return simplify(formula(FormulaType.and, subFormulas));
    }

    immutable(Formula*) or(const(immutable(Formula)*)[] subFormulas)
    {
        return simplify(formula(FormulaType.or, subFormulas));
    }

    immutable(Formula)*[immutable(Formula)*[2]] andCache;
    bool disableSimplify;
    immutable(Formula*) and(T...)(const(immutable(Formula)*) subFormula1, T subFormulas)
    {
        static if (subFormulas.length == 1)
        {
            immutable(Formula)* fa = subFormula1;
            immutable(Formula)* fb = subFormulas[0];
            if (fa > fb)
            {
                auto tmp = fa;
                fa = fb;
                fb = tmp;
            }
            if (fa is fb)
                return fa;
            if (fa is fb.negated)
                return false_;
            if (fa.isFalse || fb.isFalse)
                return false_;
            if (fa.isTrue)
                return fb;
            if (fb.isTrue)
                return fa;

            auto x = [fa, fb] in andCache;
            if (x)
                return *x;
        }
        immutable(Formula)* r = formula!T(FormulaType.and, subFormula1, subFormulas);
        if (!disableSimplify)
            r = simplify(r);
        static if (subFormulas.length == 1)
        {
            andCache[[fa, fb]] = r;
        }
        return r;
    }

    immutable(Formula*) or(T...)(const(immutable(Formula)*) subFormula1, T subFormulas)
    {
        static if (subFormulas.length == 1)
        {
            if (subFormula1 is subFormulas[0])
                return subFormula1;
            if (subFormula1 is subFormulas[0].negated)
                return true_;
            if (subFormula1.isTrue || subFormulas[0].isTrue)
                return true_;
            if (subFormula1.isFalse)
                return subFormulas[0];
            if (subFormulas[0].isFalse)
                return subFormula1;
            auto x = [subFormula1.negated, subFormulas[0].negated] in andCache;
            if (x)
                return (*x).negated;
        }
        immutable(Formula)* r = formula!T(FormulaType.or, subFormula1, subFormulas);
        if (!disableSimplify)
            r = simplify(r);
        static if (subFormulas.length == 1)
        {
            andCache[[subFormula1.negated, subFormulas[0].negated]] = r.negated;
        }
        return r;
    }

    immutable(Formula*) not(immutable Formula* f)
    {
        return f.negated;
    }

    immutable(Formula)*[immutable(Formula*)][immutable(Formula*)] removeRedundantCache;
    immutable(Formula)* removeRedundant(immutable(Formula)* f, immutable(Formula)* context)
    out (r)
    {
        checkFormula(r);
    }
    do
    {
        if (context.isFalse || context.isTrue)
            return f;
        if (f.isTrue || f.isFalse)
            return f;

        auto cacheEntry1 = context in removeRedundantCache;
        if (cacheEntry1)
        {
            auto cacheEntry2 = f in *cacheEntry1;
            if (cacheEntry2)
                return *cacheEntry2;
        }

        immutable(Formula)* r;
        if (context.type == FormulaType.and)
        {
            r = replaceAll!((f2) {
                foreach (f3; context.subFormulas)
                {
                    if (impliesSimple(f3, f2))
                        return true_;
                    if (impliesSimple(f3, f2.negated))
                        return false_;
                }
                return f2;
            })(this, f, ReplaceAllBehaviour.none);
        }
        else
        {
            r = replaceAll!((f2) {
                if (impliesSimple(context, f2))
                    return true_;
                if (impliesSimple(context, f2.negated))
                    return false_;
                return f2;
            })(this, f, ReplaceAllBehaviour.none);
        }
        if (cacheEntry1)
            (*cacheEntry1)[f] = r;
        else
            removeRedundantCache[context][f] = r;
        return r;
    }

    Tuple!(immutable(Formula)*, bool)[immutable(Formula)*[2]] distributeOrSimpleCache;
    immutable(Formula)* distributeOrSimple(immutable(Formula)* f1,
            immutable(Formula)* f2, bool nullOnComplex = false)
    {
        if ([f1, f2] in distributeOrSimpleCache)
        {
            auto r = distributeOrSimpleCache[[f1, f2]];
            if (nullOnComplex)
            {
                if (r[1])
                    return null;
                else
                    return r[0];
            }
            else
            {
                if (r[0]!is null)
                    return r[0];
            }
        }
        immutable(Formula*)[] and1;
        immutable(Formula*)[] and2;

        if (f1.type == FormulaType.and)
            and1 = f1.subFormulas_;
        else
            and1 = [f1];
        if (f2.type == FormulaType.and)
            and2 = f2.subFormulas_;
        else
            and2 = [f2];

        static Appender!(immutable(Formula)*[]) outAnd;
        size_t sizeBegin = outAnd.data.length;
        scope (exit)
            outAnd.shrinkTo(sizeBegin);
        static bool[] common1;
        static bool[] common2;
        if (common1.length < and1.length)
            common1.length = and1.length + 32;
        if (common2.length < and2.length)
            common2.length = and2.length + 32;

        common1[0 .. and1.length] = false;
        common2[0 .. and2.length] = false;
        size_t numCommon;

        foreach (i1, x1; and1)
            foreach (i2, x2; and2)
            {
                if (x1 is x2)
                {
                    outAnd.put(x1);
                    common1[i1] = true;
                    common2[i2] = true;
                    numCommon++;
                }
            }

        if (numCommon == and1.length)
        {
            distributeOrSimpleCache[[f1, f2]] = tuple!(immutable(Formula*), bool)(f1, false);
            return f1;
        }
        if (numCommon == and2.length)
        {
            distributeOrSimpleCache[[f1, f2]] = tuple!(immutable(Formula*), bool)(f2, false);
            return f2;
        }

        static Appender!(immutable(Formula)*[]) subAnd;
        scope (exit)
            subAnd.clear();
        foreach (i1, x1; and1)
        {
            if (common1[i1])
                continue;
            bool allMergeable = true;
            foreach (i2, x2; and2)
            {
                if (common2[i2])
                    continue;
                if (mergeAndImpl(x1.negated, x2.negated) is null)
                {
                    allMergeable = false;
                    break;
                }
            }
            if (allMergeable)
            {
                foreach (i2, x2; and2)
                {
                    if (common2[i2])
                        continue;
                    auto m = mergeAndImpl(x1.negated, x2.negated).negated;
                    outAnd.put(m);
                }
            }
            else
                subAnd.put(x1);
        }
        auto subAnd1 = formula(FormulaType.and, subAnd.data);
        subAnd.clear();
        foreach (i2, x2; and2)
        {
            if (common2[i2])
                continue;
            bool allMergeable = true;
            foreach (i1, x1; and1)
            {
                if (common1[i1])
                    continue;
                if (mergeAndImpl(x2.negated, x1.negated) is null)
                {
                    allMergeable = false;
                    break;
                }
            }
            if (allMergeable)
            {
                foreach (i1, x1; and1)
                {
                    if (common1[i1])
                        continue;
                    auto m = mergeAndImpl(x2.negated, x1.negated).negated;
                    outAnd.put(m);
                }
            }
            else
                subAnd.put(x2);
        }
        auto subAnd2 = formula(FormulaType.and, subAnd.data);
        immutable(Formula)* subOr = formula(FormulaType.or, subAnd1, subAnd2);
        if (subAnd1 is subAnd2.negated)
            subOr = true_;
        bool isComplex = subOr !is true_ && (subAnd1.type == FormulaType.and
                || subAnd2.type == FormulaType.and
                || (subAnd1.type != FormulaType.or && subAnd2.type != FormulaType.or));
        if (nullOnComplex && isComplex)
        {
            distributeOrSimpleCache[[f1, f2]] = tuple!(immutable(Formula*), bool)(null, true);
            return null;
        }
        outAnd.put(subOr);

        auto r = /*simplify*/ (formula(FormulaType.and, outAnd.data[sizeBegin .. $]));
        distributeOrSimpleCache[[f1, f2]] = tuple!(immutable(Formula*), bool)(r, isComplex);
        return r;
    }

    immutable(Formula)* distributeAndSimple(immutable(Formula)* f1,
            immutable(Formula)* f2, bool nullOnComplex = false)
    {
        auto r = distributeOrSimple(f1.negated, f2.negated, nullOnComplex);
        if (r is null)
            return null;
        return r.negated;
    }

    immutable(Formula)* extractCommon(immutable(Formula)* f, size_t minExtracted = 1)
    {
        if (f.type == FormulaType.or)
            return extractCommon(f.negated).negated;
        if (f.type != FormulaType.and)
            return f;

        immutable(Formula)* r;
        {
            size_t[immutable(Formula)*] subsSeen;
            size_t numOrs;
            static Appender!(immutable(Formula)*[]) nonOr;
            scope (exit)
                nonOr.clear();
            foreach (x; f.subFormulas)
            {
                if (x.type != FormulaType.or)
                {
                    nonOr.put(x);
                    continue;
                }
                numOrs++;
                foreach (x2; x.subFormulas)
                {
                    if (x2 in subsSeen)
                    {
                        subsSeen[x2]++;
                    }
                    else
                        subsSeen[x2] = 1;
                }
            }

            static Appender!(immutable(Formula)*[]) extractable;
            bool[immutable(Formula)*] extractableAA;
            scope (exit)
                extractable.clear();
            foreach (x, count; subsSeen)
            {
                if (count == numOrs)
                {
                    extractable.put(x);
                    extractableAA[x] = true;
                }
            }
            if (extractable.data.length < minExtracted)
                return f;

            static Appender!(immutable(Formula)*[]) tmp2;
            scope (exit)
                tmp2.clear();

            foreach (x; f.subFormulas)
            {
                if (x.type == FormulaType.or)
                {
                    static Appender!(immutable(Formula)*[]) tmp3;
                    scope (exit)
                        tmp3.clear();
                    foreach (immutable(Formula)* y; x.subFormulas)
                    {
                        if (y !in extractableAA)
                            tmp3.put(y);
                    }
                    auto o = formula(FormulaType.or, tmp3.data);
                    tmp2.put(o);
                }
                else
                    tmp2.put(x);
            }
            extractable.put(formula(FormulaType.and, tmp2.data));
            nonOr.put(formula(FormulaType.or, extractable.data));
            r = formula(FormulaType.and, nonOr.data);
        }
        return simplify(r);
    }

    bool orImpliesSimple(Formula.SubFormulasRange!(immutable(Formula)) aSubs,
            Formula.SubFormulasRange!(immutable(Formula)) bSubs, size_t maxDepth)
    {
        foreach (x2; aSubs)
        {
            if (!x2.isAnyLiteralFormula)
                continue;
            bool found;
            foreach (y2; bSubs)
            {
                if (x2 is y2)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }
        foreach (x2; aSubs)
        {
            if (x2.isAnyLiteralFormula)
                continue;
            bool found;
            foreach (y2; bSubs)
            {
                if (impliesSimple(x2, y2, maxDepth - 1))
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }
        return true;
    }

    bool andImpliesSimple(const(immutable(Formula)*)[] aSubs,
            const(immutable(Formula)*)[] bSubs, size_t maxDepth)
    {
        foreach (x2; bSubs)
        {
            if (!x2.isAnyLiteralFormula)
                continue;
            bool found;
            foreach (y2; aSubs)
            {
                if (y2 is x2)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }
        foreach (x2; bSubs)
        {
            if (x2.isAnyLiteralFormula)
                continue;
            bool found;
            foreach (y2; aSubs)
            {
                if (impliesSimple(y2, x2, maxDepth - 1))
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                return false;
        }
        return true;
    }

    bool[immutable(Formula)*][immutable(Formula)*] impliesCache;
    bool impliesSimple(immutable(Formula)* a, immutable(Formula)* b, size_t maxDepth = size_t.max)
    {
        if (a is b)
            return true;
        if (a.isAnyLiteralFormula && b.isAnyLiteralFormula
                && a.data.mergeKey == b.data.mergeKey && mergeAndImpl(a, b) is a)
            return true;
        if (maxDepth == 0)
            return false;
        auto x = a in impliesCache;
        auto y = (x) ? (b in *x) : null;

        impliesSimpleCacheResults[!!y]++;

        if (y)
            return *y;
        bool r;
        if (a.type == FormulaType.or && b.type == FormulaType.or)
        {
            r = orImpliesSimple(a.subFormulas, b.subFormulas, maxDepth);
        }
        else if (a.type == FormulaType.and && b.type == FormulaType.and)
        {
            r = andImpliesSimple(a.subFormulas_, b.subFormulas_, maxDepth);
        }
        else if (a.type == FormulaType.and)
        {
            r = andImpliesSimple(a.subFormulas_, (&b)[0 .. 1], maxDepth);
        }
        else if (b.type == FormulaType.or)
        {
            r = orImpliesSimple(Formula.SubFormulasRange!(immutable(Formula))((&a)[0 .. 1],
                    false), b.subFormulas, maxDepth);
        }
        else
            r = false;
        if (x)
            (*x)[b] = r;
        else
            impliesCache[a][b] = r;
        return r;
    }

    static struct IterateAssignments
    {
        LogicSystemX logicSystem;
        IterateCombination combination;
        immutable(Formula)*[typeof(T.init.mergeKey())] chosen;
        bool chooseVal(T data, FormulaType type)
        {
            auto pos = logicSystem.formula(type, data);
            auto neg = logicSystem.formula(cast(FormulaType)(type | 1), data);
            if (data.mergeKey !in chosen)
                chosen[data.mergeKey] = logicSystem.true_;
            bool posPossible = logicSystem.formula(FormulaType.and, chosen[data.mergeKey], pos) !is logicSystem.false_;
            bool negPossible = logicSystem.formula(FormulaType.and, chosen[data.mergeKey], neg) !is logicSystem.false_;
            if (posPossible && negPossible)
            {
                if (combination.next(2) == 0)
                    posPossible = false;
                else
                    negPossible = false;
            }
            if (posPossible)
            {
                chosen[data.mergeKey] = logicSystem.formula(FormulaType.and,
                        chosen[data.mergeKey], pos);
                return true;
            }
            else
            {
                chosen[data.mergeKey] = logicSystem.formula(FormulaType.and,
                        chosen[data.mergeKey], neg);
                return false;
            }
        }

        bool chooseVal(immutable(Formula)* f)
        {
            assert(f.type != FormulaType.and && f.type != FormulaType.or);
            if (f.type & 1)
                return !chooseVal(f.data, cast(FormulaType)(f.type & ~1));
            else
                return chooseVal(f.data, f.type);
        }
    }

    auto iterateAssignments()
    {
        static struct R
        {
            LogicSystemX logicSystem;
            typeof(iterateCombinations()) c;

            bool empty()
            {
                return c.empty;
            }

            IterateAssignments front()
            {
                return IterateAssignments(logicSystem, c.front);
            }

            void popFront()
            {
                c.popFront();
            }
        }

        return R(this, iterateCombinations());
    }

    immutable(Formula)*[immutable(Formula)*][immutable(Formula)*] filterImpliedCache;
    immutable(Formula)* filterImplied(immutable(Formula)* f,
            immutable(Formula)* done)
    {
        if (done.type != FormulaType.or)
            return f;
        if (f.type != FormulaType.or && f.type != FormulaType.and)
            return f;

        auto cacheX = f in filterImpliedCache;
        auto cacheY = (cacheX) ? (done in *cacheX) : null;

        if (cacheY)
            return *cacheY;

        static Appender!(immutable(Formula)*[]) innerSubFormulas;
        size_t sizeBegin = innerSubFormulas.data.length;
        scope (exit)
            innerSubFormulas.shrinkTo(sizeBegin);

        static Appender!(bool[]) usedDoneFormulas;
        size_t usedDoneFormulasSizeBegin = usedDoneFormulas.data.length;
        scope (exit)
            usedDoneFormulas.shrinkTo(usedDoneFormulasSizeBegin);

        if (f.type == FormulaType.or)
        {
            // if f contains a, b and ¬c and a=⊥, b=⊥ then the implication done means, ¬c=⊥ and ¬c can be removed
            foreach (k, y_; f.subFormulas_)
            {
                usedDoneFormulas.put(false);
            }
            foreach (i, x_; done.subFormulas_)
            {
                auto x = x_.negated; // done is Or
                size_t found = size_t.max;
                foreach (k, y_; f.subFormulas_)
                {
                    auto y = y_.negated;
                    if (impliesSimple(y.negated, x.negated))
                    {
                        usedDoneFormulas.data[usedDoneFormulasSizeBegin + k] = true;
                        found = k;
                        continue;
                    }
                }
                if (found == size_t.max)
                {
                    innerSubFormulas.put(x);
                }
            }
            bool changed = false;
            immutable(Formula)* implied;
            if (innerSubFormulas.data[sizeBegin .. $].length < done.subFormulas.length)
            {
                implied = formula(FormulaType.or, innerSubFormulas.data[sizeBegin .. $]);
            }
            innerSubFormulas.shrinkTo(sizeBegin);
            foreach (i, x_; f.subFormulas_)
            {
                auto x = x_.negated;
                if (implied !is null && !usedDoneFormulas.data[usedDoneFormulasSizeBegin + i]
                        && impliesSimple(implied, x.negated))
                {
                    changed = true;
                    continue;
                }
                else
                {
                    auto x2 = filterImplied(x, done);
                    if (x !is x2)
                        changed = true;
                    innerSubFormulas.put(x2);
                }
            }
            if (!changed)
            {
                filterImpliedCache[f][done] = f;
                return f;
            }
            else
            {
                auto x = formula(FormulaType.or, innerSubFormulas.data[sizeBegin .. $]);
                filterImpliedCache[f][done] = x;
                return x;
            }
        }
        else if (f.type == FormulaType.and)
        {
            // if f contains ¬a, ¬b and c and a=T, b=T then the implication done means, c=⊥ and c can be removed
            foreach (k, y_; f.subFormulas_)
            {
                usedDoneFormulas.put(false);
            }
            foreach (i, x_; done.subFormulas_)
            {
                auto x = x_.negated; // done is or
                size_t found = size_t.max;
                foreach (k, y_; f.subFormulas_)
                {
                    auto y = y_;
                    if (impliesSimple(y, x.negated))
                    {
                        usedDoneFormulas.data[usedDoneFormulasSizeBegin + k] = true;
                        found = k;
                        continue;
                    }
                }
                if (found == size_t.max)
                {
                    innerSubFormulas.put(x);
                }
            }
            bool changed = false;
            immutable(Formula)* implied;
            if (innerSubFormulas.data[sizeBegin .. $].length < done.subFormulas.length)
            {
                implied = formula(FormulaType.or, innerSubFormulas.data[sizeBegin .. $]);
            }
            innerSubFormulas.shrinkTo(sizeBegin);
            foreach (i, x_; f.subFormulas_)
            {
                auto x = x_;
                if (implied !is null && !usedDoneFormulas.data[usedDoneFormulasSizeBegin + i]
                        && impliesSimple(implied, x))
                {
                    changed = true;
                    continue;
                }
                else
                {
                    auto x2 = filterImplied(x, done);
                    if (x !is x2)
                        changed = true;
                    innerSubFormulas.put(x2);
                }
            }
            if (!changed)
            {
                filterImpliedCache[f][done] = f;
                return f;
            }
            else
            {
                auto x = formula(FormulaType.and, innerSubFormulas.data[sizeBegin .. $]);
                filterImpliedCache[f][done] = x;
                return x;
            }
        }
        else
            assert(false);
    }

    immutable(Formula)*[immutable(Formula)*] simplifyCache;
    //string[immutable(Formula*)] simplifyCodeVars;

    immutable(Formula)* simplify(immutable(Formula)* f)
    {
        if (f.type == FormulaType.or)
            return simplify(f.negated).negated;
        if (f.type != FormulaType.and)
            return f;
        if (f in simplifyCache)
            return simplifyCache[f];

        static Appender!(immutable(Formula)*[]) tmp;
        size_t sizeBegin = tmp.data.length;
        scope (exit)
            tmp.shrinkTo(sizeBegin);

        bool[immutable(Formula)*] done;
        foreach (x; f.subFormulas_) // f is and
        {
            //done[x] = true;
            auto x2 = simplify(x);
            //if (x2 !is x)
            done[x2] = true;
            if (x2 !is true_)
                tmp.put(x2);
        }

        bool changed;
        do
        {
            changed = false;

            // remove subsets like (a∨b∨c)∧(a∨b)
            for (size_t i = sizeBegin; i < tmp.data.length;)
            {
                auto x = tmp.data[i];
                if (x is true_)
                {
                    foreach (y; tmp.data[sizeBegin .. $])
                        writeln("========== ", y.toString);
                    assert(false);
                }
                bool foundSubset;
                for (size_t k = sizeBegin; k < tmp.data.length; k++)
                {
                    if (k == i)
                        continue;
                    auto y = tmp.data[k];
                    if (impliesSimple(y, x))
                    {
                        foundSubset = true;
                    }
                }
                if (foundSubset)
                {
                    done.remove(x);
                    tmp.data[i] = tmp.data[$ - 1];
                    tmp.shrinkTo(tmp.data.length - 1);
                    changed = true;
                }
                else
                    i++;
            }

            // find sets with everything the same except one part, that is opposite:
            // (a∨b∨c)Λ(a∨b∨¬c)   => (a∨b)
            for (size_t i = sizeBegin; i < tmp.data.length;)
            {
                auto x = tmp.data[i];
                size_t matchingFormula = size_t.max;
                immutable(Formula)* mergedFormula;
                for (size_t k = sizeBegin; k < i; k++)
                {
                    if (k == i)
                        continue;
                    auto y = tmp.data[k];

                    auto merged = distributeAndSimple(x, y, true);
                    if (merged !is null)
                    {
                        mergedFormula = merged;
                        matchingFormula = k;
                    }
                }
                if (matchingFormula != size_t.max)
                {
                    auto y = tmp.data[matchingFormula];
                    auto o = mergedFormula;

                    done.remove(x);
                    done.remove(tmp.data[matchingFormula]);
                    tmp.data[i] = tmp.data[$ - 1];
                    tmp.shrinkTo(tmp.data.length - 1);
                    if (o.type == FormulaType.and && o.subFormulas.length)
                    {
                        foreach (k, z; o.subFormulas_)
                        {
                            if (k == 0)
                                tmp.data[matchingFormula] = z;
                            else
                                tmp.put(z);
                            done[z] = true;
                        }
                    }
                    else
                    {
                        done[o] = true;
                        tmp.data[matchingFormula] = o;
                    }
                    changed = true;
                }
                else
                    i++;
            }

            for (size_t i = sizeBegin; i < tmp.data.length;)
            {
                auto x = tmp.data[i];
                if (x.type == FormulaType.or)
                {
                    tmp.data[i] = null;
                    immutable(Formula)* x2a = filterDone(x, tmp.data[sizeBegin .. $]);
                    immutable(Formula)* x2 = x2a;
                    foreach (doneF; tmp.data[sizeBegin .. $])
                        if (doneF !is null)
                        {
                            auto x2old = x2;
                            x2 = filterImplied(x2, doneF);
                        }
                    tmp.data[i] = x;
                    if (x2 !is x)
                    {
                        x2 = simplify(x2);
                    }
                    if (x2.type == FormulaType.or)
                        x2 = extractCommon(x2, 1);
                    if (x2 is true_)
                    {
                        tmp.data[i] = tmp.data[$ - 1];
                        tmp.shrinkTo(tmp.data.length - 1);
                    }
                    else if (x2 is false_)
                    {
                        simplifyCache[f] = false_;
                        return false_;
                    }
                    else if (x2.type == FormulaType.and)
                    {
                        tmp.data[i] = tmp.data[$ - 1];
                        tmp.shrinkTo(tmp.data.length - 1);

                        foreach (x3; x2.subFormulas_)
                        {
                            if (x3 !in done)
                            {
                                done[x3] = true;
                                changed = true;
                                tmp.put(x3);
                            }
                        }
                    }
                    else
                    {
                        if (x2 !in done)
                        {
                            done[x2] = true;
                            changed = true;
                        }
                        tmp.data[i] = x2;
                        i++;
                    }
                }
                else
                    i++;
            }
        }
        while (changed);

        auto r = formula(FormulaType.and, tmp.data[sizeBegin .. $]);
        simplifyCache[f] = r;
        return r;
    }

    immutable(Formula)* mergeAndImpl(immutable(Formula)* f1, immutable(Formula)* f2)
    {
        if (!f1.isAnyLiteralFormula || !f2.isAnyLiteralFormula)
            return null;
        if (f1.data.mergeKey != f2.data.mergeKey)
            return null;
        T data1 = f1.data;
        FormulaType type1 = f1.type;
        T data2 = f2.data;
        FormulaType type2 = f2.type;
        MergeAndResult r = data1.mergeAnd(type1, data2, type2);
        if (r == MergeAndResult.false_)
            return false_;
        if (r == MergeAndResult.two)
            return null;
        return formula(type1, data1);
    }

    immutable(Formula)* mergeAnd(immutable(Formula)* f1, immutable(Formula)* f2)
    {
        auto r = mergeAndImpl(f1, f2);
        if (r is null)
            return and(f1, f2);
        else
            return r;
    }

    immutable(Formula)* simpleBigOr(immutable(Formula)* a, immutable(Formula)* b)
    {
        if (a.isFalse)
            return b;
        if (b.isFalse)
            return a;
        bool[immutable(Formula)*] foundA;
        Appender!(immutable(Formula)*[]) result;
        if (a.type == FormulaType.and)
        {
            foreach (x; a.subFormulas)
                foundA[x] = true;
        }
        else
            foundA[a] = true;
        if (b.type == FormulaType.and)
        {
            foreach (x; b.subFormulas)
                if (x in foundA)
                    result.put(x);
        }
        else if (b in foundA)
            result.put(b);
        return and(result.data);
    }
}

enum MergeAndResult
{
    false_, // and(this, rhs) is always false
    one, // and(this, rhs) can be simplified into one that is stored into this
    two // and(this, rhs) cannot be simplified
}

struct SimpleLiteral
{
    static enum FormulaType : ubyte
    {
        literal,
        notLiteral,
        and,
        or,
    }

    string name;
    void toString(O)(ref O outRange, FormulaType type) const
    {
        if (type & 1)
            outRange.put("¬");
        outRange.put(name);
    }

    string toStringCode(FormulaType type) const
    {
        Appender!string app;
        if (type & 1)
            app.put("notLiteral(\"");
        else
            app.put("literal(\"");
        app.put(name);
        app.put("\")");
        return app.data;
    }

    int opCmp(ref const SimpleLiteral rhs) const
    {
        if (name < rhs.name)
            return -1;
        if (name > rhs.name)
            return 1;
        return 0;
    }

    enum isSimple = true;

    string mergeKey() const
    {
        return name;
    }

    MergeAndResult mergeAnd(ref FormulaType thisType, const ref SimpleLiteral rhs,
            FormulaType rhsType)
    {
        bool thisNegated = !!(thisType & 1);
        bool rhsNegated = !!(rhsType & 1);
        if (thisNegated == rhsNegated)
            return MergeAndResult.one;
        else
            return MergeAndResult.false_;
    }
}

class SimpleLogicSystem : LogicSystemX!(SimpleLiteral)
{
    immutable(FormulaX!SimpleLiteral*) literal(string name)
    {
        return formula(FormulaType.literal, SimpleLiteral(name));
    }

    immutable(FormulaX!SimpleLiteral*) notLiteral(string name)
    {
        return formula(FormulaType.notLiteral, SimpleLiteral(name));
    }
}

struct BoundLiteral
{
    static enum FormulaType : ubyte
    {
        literal,
        notLiteral,
        and,
        or,
        greaterEq,
        less
    }

    string name;
    long number;

    void toString(O)(ref O outRange, FormulaType type) const
    {
        bool isBound = type == FormulaType.greaterEq || type == FormulaType.less;
        if (!isBound)
        {
            if (number == 0)
            {
                if (type & 1)
                    outRange.put("¬");
                outRange.put(name);
            }
            else
            {
                outRange.put(name);
                if (type & 1)
                    outRange.put(" == ");
                else
                    outRange.put(" ≠ ");
                outRange.put(text(number));
            }
        }
        else
        {
            outRange.put(name);
            if (type & 1)
                outRange.put(" < ");
            else
                outRange.put(" ≥ ");
            outRange.put(text(number));
        }
    }

    int opCmp(ref const BoundLiteral rhs) const
    {
        if (name < rhs.name)
            return -1;
        if (name > rhs.name)
            return 1;
        if (number < rhs.number)
            return -1;
        if (number > rhs.number)
            return 1;
        return 0;
    }

    string mergeKey() const
    {
        return name;
    }

    MergeAndResult mergeAnd(ref FormulaType thisType, const ref BoundLiteral rhs,
            FormulaType rhsType)
    {
        bool isBound = thisType == FormulaType.greaterEq || thisType == FormulaType.less;
        bool rhsIsBound = rhsType == FormulaType.greaterEq || rhsType == FormulaType.less;
        bool thisNegated = !!(thisType & 1);
        bool rhsNegated = !!(rhsType & 1);
        if (!thisNegated && !rhsNegated)
        {
            if (!isBound && !rhsIsBound) // x!=number && x!=rhs.number
            {
                if (number == rhs.number)
                    return MergeAndResult.one;
                else
                    return MergeAndResult.two;
            }
            else if (isBound && rhsIsBound) // x>=number && x>=rhs.number
            {
                if (number >= rhs.number)
                    return MergeAndResult.one;
                else
                {
                    number = rhs.number;
                    return MergeAndResult.one;
                }
            }
            else if (!isBound && rhsIsBound) // x!=number && x>=rhs.number
            {
                if (number < rhs.number)
                {
                    number = rhs.number;
                    isBound = true;
                    thisType = FormulaType.greaterEq;
                    return MergeAndResult.one;
                }
                else if (number == rhs.number)
                {
                    number = rhs.number + 1;
                    isBound = true;
                    thisType = FormulaType.greaterEq;
                    return MergeAndResult.one; // x>rhs.number
                }
                else
                    return MergeAndResult.two;
            }
            else if (isBound && !rhsIsBound) // x>=number && x!=rhs.number
            {
                if (number > rhs.number)
                {
                    return MergeAndResult.one;
                }
                else if (number == rhs.number)
                {
                    number = number + 1;
                    return MergeAndResult.one; // x>number
                }
                else
                    return MergeAndResult.two;
            }
            else
                assert(false);
        }
        else if (!thisNegated && rhsNegated)
        {
            if (!isBound && !rhsIsBound) // x!=number && x==rhs.number
            {
                if (number == rhs.number)
                    return MergeAndResult.false_;
                else
                {
                    number = rhs.number;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x==rhs.number
                }
            }
            else if (isBound && rhsIsBound) // x>=number && x<rhs.number
            {
                if (number >= rhs.number)
                    return MergeAndResult.false_;
                else if (number + 1 == rhs.number)
                {
                    isBound = false;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x==number
                }
                else
                {
                    return MergeAndResult.two;
                }
            }
            else if (!isBound && rhsIsBound) // x!=number && x<rhs.number
            {
                if (number > rhs.number - 1)
                {
                    number = rhs.number;
                    thisNegated = true;
                    thisType = FormulaType.less;
                    isBound = true;
                    return MergeAndResult.one;
                }
                else if (number == rhs.number - 1)
                {
                    number = rhs.number - 1;
                    thisNegated = true;
                    thisType = FormulaType.less;
                    isBound = true;
                    return MergeAndResult.one;
                }
                else
                    return MergeAndResult.two;
            }
            else if (isBound && !rhsIsBound) // x>=number && x==rhs.number
            {
                if (rhs.number >= number)
                {
                    number = rhs.number;
                    isBound = false;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x == rhs.number;
                }
                else
                    return MergeAndResult.false_;
            }
            else
                assert(false);
        }
        else if (thisNegated && !rhsNegated)
        {
            if (!isBound && !rhsIsBound) // x==number && x!=rhs.number
            {
                if (number == rhs.number)
                    return MergeAndResult.false_;
                else
                {
                    return MergeAndResult.one; // x==number
                }
            }
            else if (isBound && rhsIsBound) // x<number && x>=rhs.number
            {
                if (rhs.number >= number)
                    return MergeAndResult.false_;
                else if (rhs.number + 1 == number)
                {
                    number = rhs.number;
                    isBound = false;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x==number
                }
                else
                {
                    return MergeAndResult.two;
                }
            }
            else if (!isBound && rhsIsBound) // x==number && x>=rhs.number
            {
                if (number >= rhs.number)
                {
                    isBound = false;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x == number;
                }
                else
                    return MergeAndResult.false_;
            }
            else if (isBound && !rhsIsBound) // x<number && x!=rhs.number
            {
                if (rhs.number > number - 1)
                {
                    return MergeAndResult.one;
                }
                else if (rhs.number == number - 1)
                {
                    number = number - 1;
                    return MergeAndResult.one;
                }
                else
                    return MergeAndResult.two;
            }
            else
                assert(false);
        }
        else if (thisNegated && rhsNegated)
        {
            if (!isBound && !rhsIsBound) // x==number && x==rhs.number
            {
                if (number == rhs.number)
                    return MergeAndResult.one;
                else
                {
                    return MergeAndResult.false_;
                }
            }
            else if (isBound && rhsIsBound) // x<number && x<rhs.number
            {
                if (number < rhs.number)
                    return MergeAndResult.one;
                else
                {
                    number = rhs.number;
                    return MergeAndResult.one;
                }
            }
            else if (!isBound && rhsIsBound) // x==number && x<rhs.number
            {
                if (number < rhs.number)
                {
                    return MergeAndResult.one;
                }
                else
                    return MergeAndResult.false_;
            }
            else if (isBound && !rhsIsBound) // x<number && x==rhs.number
            {
                if (rhs.number < number)
                {
                    number = rhs.number;
                    isBound = false;
                    thisNegated = true;
                    thisType = FormulaType.notLiteral;
                    return MergeAndResult.one; // x == rhs.number;
                }
                else
                    return MergeAndResult.false_;
            }
            else
                assert(false);
        }
        else
            assert(false);
    }
}

class BoundLogicSystem : LogicSystemX!(BoundLiteral)
{
    this()
    {
    }

    this(BoundLogicSystem orig)
    {
        super(orig);
    }

    immutable(FormulaX!BoundLiteral*) literal(string name)
    {
        return formula(FormulaType.literal, BoundLiteral(name.idup, 0));
    }

    immutable(FormulaX!BoundLiteral*) notLiteral(string name)
    {
        return formula(FormulaType.notLiteral, BoundLiteral(name.idup, 0));
    }

    immutable(FormulaX!BoundLiteral)* boundLiteral(string name, string op, long number)
    {
        if (op == "==")
            return formula(FormulaType.notLiteral, BoundLiteral(name.idup, number));
        if (op == "!=" || op == "≠")
            return formula(FormulaType.literal, BoundLiteral(name.idup, number));
        if (op == ">=" || op == "≥")
            return formula(FormulaType.greaterEq, BoundLiteral(name.idup, number));
        if (op == "<")
            return formula(FormulaType.less, BoundLiteral(name.idup, number));
        if (op == ">")
            return boundLiteral(name, ">=", number + 1);
        if (op == "<=" || op == "≤")
            return boundLiteral(name, "<", number + 1);
        assert(false);
    }

    immutable(FormulaX!BoundLiteral)* boundLiteral(long number, string op, string name)
    {
        if (op == "==")
            return boundLiteral(name, "==", number);
        if (op == "!=" || op == "≠")
            return boundLiteral(name, "!=", number);
        if (op == "<")
            return boundLiteral(name, ">", number);
        if (op == ">")
            return boundLiteral(name, "<", number);
        if (op == "<=" || op == "≤")
            return boundLiteral(name, ">=", number);
        if (op == ">=" || op == "≥")
            return boundLiteral(name, "<=", number);
        assert(false);
    }
}

bool isSimple(const FormulaX!SimpleLiteral* f)
{
    return true;
}

bool isSimple(const FormulaX!BoundLiteral* f)
{
    return (f.type == BoundLiteral.FormulaType.literal || BoundLiteral.FormulaType.notLiteral)
        && f.data.number == 0;
}

static foreach (LogicSystem; AliasSeq!(SimpleLogicSystem, BoundLogicSystem))
{
    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f = and([or([literal("A"), literal("B")]), notLiteral("C")]);
            assert(f.toString == "(¬C ∧ (A ∨ B))");
            auto f2 = and([notLiteral("C"), or([literal("B"), literal("A")])]);
            assert(f2 is f);
            auto f3 = and([or([literal("B"), literal("A")]), notLiteral("C")]);
            assert(f3 is f);
            auto f4 = and([notLiteral("C"), or([literal("A"), literal("B")])]);
            assert(f4 is f);

            auto f5 = not(or([
                    and([notLiteral("A"), notLiteral("B")]), literal("C")
            ]));
            assert(f5 is f);
            auto f6 = not(not(not(or([
                        and([notLiteral("A"), notLiteral("B")]), literal("C")
            ]))));
            assert(f6 is f);

            auto f7 = and([
                and([
                    and([or([or([literal("A"), or([literal("B")])])])]),
                    notLiteral("C")
                ])
            ]);
            assert(f7 is f);

            auto f8 = and([
                or([literal("A"), literal("A"), literal("B"), literal("A")]),
                or([literal("A"), literal("B")]), notLiteral("C"), notLiteral("C")
            ]);
            assert(f8 is f);
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f = and(or(literal("A"), literal("B")), notLiteral("C"));
            assert(f.toString == "(¬C ∧ (A ∨ B))");
            auto f2 = and(notLiteral("C"), or(literal("B"), literal("A")));
            assert(f2 is f);
            auto f3 = and(or(literal("B"), literal("A")), notLiteral("C"));
            assert(f3 is f);
            auto f4 = and(notLiteral("C"), or(literal("A"), literal("B")));
            assert(f4 is f);

            auto f5 = not(or(and(notLiteral("A"), notLiteral("B")), literal("C")));
            assert(f5 is f);
            auto f6 = not(not(not(or(and(notLiteral("A"), notLiteral("B")), literal("C")))));
            assert(f6 is f);

            auto f7 = and(and(and(or(or(literal("A"), or(literal("B"))))), notLiteral("C")));
            assert(f7 is f);

            auto f8 = and(or(literal("A"), literal("A"), literal("B"),
                    literal("A")), or(literal("A"), literal("B")),
                    notLiteral("C"), notLiteral("C"));
            assert(f8 is f);
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            assert(and([]).toString == "⊤");
            assert(or([]).toString == "⊥");
            assert(and([]) is true_);
            assert(or([]) is false_);
            auto f1 = and([literal("A"), notLiteral("A"), literal("C")]);
            assert(f1 is false_);
            auto f2 = or([literal("A"), notLiteral("A"), literal("C")]);
            assert(f2 is true_);
            auto f3 = or([literal("A"), true_, literal("C")]);
            assert(f3 is true_);
            auto f4 = or([literal("A"), false_, literal("C")]);
            assert(f4 is or([literal("A"), literal("C")]));
            auto f5 = and([literal("A"), true_, literal("C")]);
            assert(f5 is and([literal("A"), literal("C")]));
            auto f6 = and([literal("A"), false_, literal("C")]);
            assert(f6 is false_);
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = simplify(and([
                    or([literal("A"), literal("B")]), literal("A")
            ]));
            assert(f1 is literal("A"));
            auto f2 = simplify(and([
                    or([literal("A"), literal("B")]), notLiteral("A")
            ]));
            assert(f2 is and([notLiteral("A"), literal("B")]));

            auto f3 = simplify(and([
                    or([literal("A"), literal("B")]), literal("A"), literal("B")
            ]));
            assert(f3 is and([literal("A"), literal("B")]));
            auto f4 = simplify(and([
                    or([literal("A"), literal("B")]), notLiteral("A"),
                    notLiteral("B")
            ]));
            assert(f4 is false_);

            auto f5 = simplify(and([
                    or([literal("A"), literal("B")]), literal("A"),
                    notLiteral("B")
            ]));
            assert(f5 is and([literal("A"), notLiteral("B")]));
            auto f6 = simplify(and([
                    or([literal("A"), literal("B")]), notLiteral("A"),
                    literal("B")
            ]));
            assert(f6 is and([notLiteral("A"), literal("B")]));
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or([
                and([
                    notLiteral("defined(STBTT_STATIC)"),
                    notLiteral("defined(__STB_INCLUDE_STB_TRUETYPE_H__)")
                ]),
                and([
                    literal("defined(STBTT_STATIC)"),
                    notLiteral("defined(__STB_INCLUDE_STB_TRUETYPE_H__)")
                ])
            ]);
            auto f2 = or([
                literal("defined(STBTT_STATIC)"),
                literal("defined(__STB_INCLUDE_STB_TRUETYPE_H__)")
            ]);
            auto f3 = simplify(and([f1, f2]));
            assert(
                    f3.toString
                    == "(defined(STBTT_STATIC) ∧ ¬defined(__STB_INCLUDE_STB_TRUETYPE_H__))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = notLiteral("defined(TESTINCLUDE_H)");
            auto f2 = and(or(literal("defined(DEF)"), literal("defined(TESTINCLUDE_H)")),
                    or(notLiteral("defined(DEF)"), literal("defined(TESTINCLUDE_H)")));
            auto f3 = simplify(and([f1, f2]));
            assert(f3 is false_);
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            // cpptests2/testinclude4c.cpp
            auto f1 = and(notLiteral("defined(DEF)"), notLiteral("defined(TESTINCLUDE_H)"));
            auto f2 = and(literal("defined(DEF)"), notLiteral("defined(TESTINCLUDE_H)"));
            auto f3 = or(f1, f2);
            auto f4 = and(f3, f1);
            assert(f4.toString == "(¬defined(DEF) ∧ ¬defined(TESTINCLUDE_H))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = and(literal("a"), literal("b"), literal("c"));
            auto f3 = or(f1, literal("d"));
            auto f4 = and(f3, literal("f"), literal("g"));
            assert(f4.toString == "(f ∧ g ∧ (d ∨ (a ∧ b ∧ c)))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), and(literal("b"), notLiteral("a")));
            assert(f1.toString == "(a ∨ b)");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            assert(impliesSimple(and(literal("a"), literal("b"), literal("c")),
                    and(literal("a"), literal("b"), literal("c"))));
            assert(impliesSimple(and(literal("a"), literal("b"), literal("c")),
                    and(literal("a"), literal("b"))));
            assert(!impliesSimple(and(literal("a"), literal("c")),
                    and(literal("a"), literal("b"), literal("c"))));

            assert(impliesSimple(or(literal("a"), literal("b"), literal("c")),
                    or(literal("a"), literal("b"), literal("c"))));
            assert(!impliesSimple(or(literal("a"), literal("b"),
                    literal("c")), or(literal("a"), literal("b"))));
            assert(impliesSimple(or(literal("a"), literal("b")),
                    or(literal("a"), literal("b"), literal("c"))));

            assert(!impliesSimple(and(literal("c"), or(literal("a"),
                    literal("b"))), and(literal("a"), literal("c"))));
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), literal("b"), and(literal("c"), literal("d")));
            auto f2 = or(literal("a"), and(literal("c"), literal("d"), literal("e")));
            auto f3 = and(f1, f2);
            assert(f3.toString == "(a ∨ (c ∧ d ∧ e))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("b"), and(literal("c"), literal("d")));
            auto f2 = and(literal("a"), f1);
            auto f3 = or(literal("b"), and(literal("e"), literal("f")));
            assert(and(f1, f3).toString == "(b ∨ (c ∧ d ∧ e ∧ f))");
            assert(distributeAndSimple(f1, f3).toString == "(b ∨ (c ∧ d ∧ e ∧ f))");
            assert(and(f2, f3).toString == "(a ∧ (b ∨ (c ∧ d ∧ e ∧ f)))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), literal("b"), and(literal("c"), literal("d")));
            auto f2 = and(literal("c"), literal("d"), literal("e"));
            auto f3 = and(f1, f2);
            assert(f3.toString == "(c ∧ d ∧ e)");
        }
    }

    unittest  // see filterImplied
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), literal("b"), notLiteral("c"), literal("d"));
            auto f2 = or(literal("a"), literal("b"), literal("c")); // ¬a ∧ ¬b => c
            auto f3 = and(f1, f2);
            assert(f3.toString == "((a ∨ b ∨ c) ∧ (a ∨ b ∨ d))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), literal("b"), literal("c"), literal("d"));
            auto f2 = or(literal("a"), literal("b"), literal("c")); // ¬a ∧ ¬b => c
            auto f3 = and(f1, f2);
            assert(f3.toString == "(a ∨ b ∨ c)");
        }
    }

    unittest  // see filterImplied
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = or(literal("a"), and(notLiteral("b"), notLiteral("c")), literal("d"));
            auto f2 = or(literal("a"), literal("b"), literal("c")); // ¬a => b ∨ c
            auto f3 = and(f1, f2);
            assert(f3.toString == "((a ∨ b ∨ c) ∧ (a ∨ d))");
        }
    }

    unittest
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = and(notLiteral("a"), notLiteral("b"), notLiteral("c"), literal("d"));
            auto f2 = or(f1, literal("e"));
            auto f3 = or(literal("a"), literal("b"), literal("c")); // ¬a ∧ ¬b => c
            auto f4 = and(f2, f3);
            assert(f4.toString == "(e ∧ (a ∨ b ∨ c))");
        }
    }

    unittest  // see filterImplied
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = and(notLiteral("a"), notLiteral("b"), literal("c"), literal("d"));
            auto f2 = or(f1, literal("e"));
            auto f3 = or(literal("a"), literal("b"), literal("c")); // ¬a ∧ ¬b => c
            auto f4 = and(f2, f3);
            assert(f4.toString == "((a ∨ b ∨ c) ∧ (e ∨ (¬a ∧ ¬b ∧ d)))");
        }
    }

    unittest  // see filterImplied
    {
        LogicSystem s = new LogicSystem();
        with (s)
        {
            auto f1 = and(notLiteral("a"), or(literal("b"), literal("c")), literal("d"));
            auto f2 = or(f1, literal("e"));
            auto f3 = or(literal("a"), literal("b"), literal("c")); // ¬a => b ∨ c
            auto f4 = and(f2, f3);
            assert(f4.toString == "((a ∨ b ∨ c) ∧ (e ∨ (¬a ∧ d)))");
        }
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        assert(boundLiteral("a", ">=", 4).toString == "a ≥ 4");
        assert(and(boundLiteral("a", ">=", 4), boundLiteral("a", "<", 10))
                .toString == "(a ≥ 4 ∧ a < 10)");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        immutable(BoundLogicSystem.Formula)*[] formulas;
        foreach (op; ["==", "!=", ">=", "<"])
            foreach (n; -2 .. 5)
                formulas ~= boundLiteral("x", op, n);
        foreach (i, f1; formulas)
            foreach (f2; formulas[0 .. i + 1])
            {
                auto f12 = mergeAnd(f1, f2);
                auto f21 = mergeAnd(f2, f1);
                assert(f12 is f21);
                bool allFalse = true;
                foreach (n; -5 .. 10)
                {
                    auto val1 = f1.boundEvaluate!(x => n);
                    auto val2 = f2.boundEvaluate!(x => n);
                    auto val12 = f12.boundEvaluate!(x => n);
                    auto val21 = f21.boundEvaluate!(x => n);
                    assert(val12 == (val1 && val2));
                    assert(val21 == (val1 && val2));
                    if (val1 && val2)
                        allFalse = false;
                }
                if (allFalse)
                    assert(f12 is false_);

                foreach (f3; formulas)
                {
                    bool isBetter = true;
                    foreach (n; -5 .. 10)
                    {
                        auto val1 = f1.boundEvaluate!(x => n);
                        auto val2 = f2.boundEvaluate!(x => n);
                        auto val3 = f3.boundEvaluate!(x => n);
                        if (val3 != (val1 && val2))
                            isBetter = false;
                    }
                    if (isBetter)
                        assert(f12 is f3, f3.toString);
                }

                assert(and(f1, f2) is f12);
                assert(and(f2, f1) is f21);
            }
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        auto f1 = and(boundLiteral("x", ">=", 500), boundLiteral("x", "<",
                600), boundLiteral("x", ">=", 700));
        assert(f1.toString == "⊥");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        auto f1 = or(boundLiteral("x", "≥", 10), literal("a"));
        auto f2 = and(boundLiteral("x", "≥", 5), f1);
        assert(f2.toString == "(x ≥ 5 ∧ (a ∨ x ≥ 10))");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        s.disableSimplify = true;
        auto f1 = and(notLiteral("a"), notLiteral("b"), notLiteral("c"));
        auto f2 = and(notLiteral("a"), notLiteral("b"), notLiteral("c"), literal("d"));
        auto f3 = and(notLiteral("a"), notLiteral("b"), notLiteral("c"), literal("e"));
        auto f4 = and(notLiteral("a"), notLiteral("b"), notLiteral("c"), literal("f"));
        auto f5 = or(f2, f3);
        auto f6 = or(f1, f4);
        auto f7 = and(literal("d"), f5, f6);
        assert(f7.toString == "(d ∧ ((¬a ∧ ¬b ∧ ¬c) ∨ (¬a ∧ ¬b ∧ ¬c ∧ f)) ∧ ((¬a ∧ ¬b ∧ ¬c ∧ d) ∨ (¬a ∧ ¬b ∧ ¬c ∧ e)))");
        auto f8 = simplify(f7);
        assert(f8.toString == "(¬a ∧ ¬b ∧ ¬c ∧ d)");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        auto f1 = or(literal("a"), literal("b"), and(literal("c"), literal("d"), literal("e")));
        auto f2 = and(literal("f"), or(literal("a"), literal("b"),
                and(literal("c"), literal("d")), and(literal("g"),
                literal("h")), and(literal("c"), literal("d"))));
        auto f3 = s.removeRedundant(f2, f1);
        assert(f3.toString == "f");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        disableSimplify = true;
        auto f1 = and(boundLiteral("_XOPEN_SOURCE", "<", 500),
                literal("defined(_XOPEN_SOURCE)"), literal("defined(_XOPEN_SOURCE_EXTENDED)"));
        auto f2 = and(boundLiteral("_XOPEN_SOURCE", ">=", 500), literal("defined(_XOPEN_SOURCE)"));
        auto f3 = or(f1, f2);
        auto f4 = and(boundLiteral("_XOPEN_SOURCE", ">=", 600), literal("defined(_XOPEN_SOURCE)"));
        auto f5 = or(literal("defined(_POSIX_C_SOURCE)"), f4);
        immutable(Formula)* f6 = and(f3, f5);
        assert(f6.toString == "((defined(_POSIX_C_SOURCE) ∨ (_XOPEN_SOURCE ≥ 600 ∧ defined(_XOPEN_SOURCE))) ∧ ((_XOPEN_SOURCE < 500 ∧ defined(_XOPEN_SOURCE) ∧ defined(_XOPEN_SOURCE_EXTENDED)) ∨ (_XOPEN_SOURCE ≥ 500 ∧ defined(_XOPEN_SOURCE))))");
        f6 = simplify(f6);
        assert(f6.toString == "(defined(_XOPEN_SOURCE) ∧ (_XOPEN_SOURCE ≥ 500 ∨ defined(_XOPEN_SOURCE_EXTENDED)) ∧ (_XOPEN_SOURCE ≥ 600 ∨ defined(_POSIX_C_SOURCE)))");
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        auto f1 = or(notLiteral("defined(_WIN32)"), literal("defined(__CYGWIN__)"));
        auto f2 = and(notLiteral("defined(GIT_WIN32)"), f1);
        auto f3 = and(literal("defined(_WIN32)"), notLiteral("defined(__CYGWIN__)"));
        auto f4 = or(literal("defined(GIT_WIN32)"), f3);
        auto f5 = and(f2, f4);
        assert(f5 is false_);
        auto f6 = and(and(f2, literal("X")), f4);
        assert(f6 is false_);
    }
}

unittest
{
    BoundLogicSystem s = new BoundLogicSystem();
    with (s)
    {
        // condition
        auto f3 = and(boundLiteral("Inc", "<", 1), literal("__USE_MISC"));
        auto f5 = and(boundLiteral("Inc", "≥", 2));
        auto f6 = and(boundLiteral("Inc", "==", 1), notLiteral("__USE_MISC"));
        auto f7 = or(f6, f3);
        auto f8 = or(f5, literal("__USE_POSIX199506"));
        auto f9 = and(f8, f7);

        // d.condition
        auto f10 = and(boundLiteral("Inc", "<", 1),
                literal("__USE_POSIX199506"), literal("__USE_MISC"));
        auto f13 = or(f5, f6, f10);

        auto x = and(f9, f13);
        assert(x.toString
                == "((Inc ≥ 2 ∨ __USE_POSIX199506) ∧ ((Inc == 1 ∧ ¬__USE_MISC) ∨ (Inc < 1 ∧ __USE_MISC)))");
    }
}
