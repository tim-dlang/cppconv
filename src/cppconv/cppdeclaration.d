
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppdeclaration;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cpptype;
import cppconv.mergedfile;
import cppconv.runcppcommon;
import std.algorithm;
import std.array;
import std.stdio;

class DeclarationSet
{
    static struct Entry
    {
        Declaration data;

        immutable(Formula)* condition() const
        {
            return data.condition;
        }

        void condition(immutable(Formula)* n)
        {
            data.condition = n;
        }
    }

    Scope scope_;
    string name;
    bool outsideSymbolTable;
    Entry[] entries;
    Entry[] entriesRedundant;
    immutable(Formula)* conditionAll;
    immutable(Formula)* conditionType;

    this(string name, Scope scope_)
    {
        this.name = name;
        this.scope_ = scope_;
    }

    void addNew(Declaration data, LogicSystem logicSystem, bool checkRedundant)
    {
        assert(data.declarationSet is null || data.declarationSet is this);
        data.declarationSet = this;
        if (conditionAll is null)
            conditionAll = data.condition;
        else
            conditionAll = logicSystem.or(conditionAll, data.condition);

        if (conditionType is null)
            conditionType = logicSystem.false_;
        bool isRedundant;
        if (checkRedundant && data.type == DeclarationType.type
                && (data.flags & DeclarationFlags.forward) != 0)
        {
            if (logicSystem.and(data.condition, conditionType.negated).isFalse)
                isRedundant = true;
        }
        if (data.type == DeclarationType.type)
        {
            conditionType = logicSystem.or(conditionType, data.condition);
        }

        if (isRedundant)
        {
            data.isRedundant = true;
            entriesRedundant ~= Entry(data);
        }
        else
        {
            data.isRedundant = false;
            entries ~= Entry(data);
        }
    }

    void updateCondition(Declaration data, immutable(Formula)* condition,
            LogicSystem logicSystem, bool checkRedundant)
    {
        conditionAll = logicSystem.or(conditionAll, data.condition);

        bool isRedundant;
        if (checkRedundant && data.type == DeclarationType.type
                && (data.flags & DeclarationFlags.forward) != 0)
        {
            if (logicSystem.and(data.condition, conditionType.negated).isFalse)
                isRedundant = true;
        }
        if (data.type == DeclarationType.type)
        {
            conditionType = logicSystem.or(conditionType, data.condition);
        }

        if (!isRedundant && data.type == DeclarationType.type
                && (data.flags & DeclarationFlags.forward) != 0)
        {
            data.isRedundant = false;
            foreach (i, e; entriesRedundant)
            {
                if (e.data is data)
                {
                    entries ~= e;
                    entriesRedundant[i] = entriesRedundant[$ - 1];
                    entriesRedundant.length--;
                    break;
                }
            }
        }

        data.condition = condition;
    }
}

enum ExtraScopeType
{
    unknown,
    parentClass,
    namespace,
    parameter,
    template_,
    inlineNamespace,
}

struct ExtraScope
{
    ExtraScopeType type;
    Scope scope_;
}

class Scope
{
    Scope parentScope;
    Tree tree;
    immutable(Formula)* scopeCondition;

    ConditionMap!ExtraScope extraParentScopes;

    Scope[][string] subScopes;
    Scope[Tree] childScopeByTree;
    Scope[string] childNamespaces;

    size_t numFunctionScopes;
    size_t numFunctionParamScopes;
    size_t numTemplateParamScopes;

    bool currentlyInsideParams;

    bool initialized;

    this(Tree tree, immutable(Formula)* scopeCondition)
    {
        this.tree = tree;
        this.scopeCondition = scopeCondition;
    }

    final void realizeForwardScope(string name, LogicSystem logicSystem)
    {
        static size_t recursionDepth;
        recursionDepth++;
        scope (exit)
            recursionDepth--;
        scope (failure)
            writeln("realizeForwardScope failure ", name, " ", toString);
        if (recursionDepth > 1000)
            throw new Exception("realizeForwardScope recursion limit exceeded");

        if (parentScope is null)
            return;
        foreach (s2; extraParentScopes.entries)
            if (s2.data.type != ExtraScopeType.inlineNamespace)
                s2.data.scope_.realizeForwardScope(name, logicSystem);
        parentScope.realizeForwardScope(name, logicSystem);
        immutable(Formula)* conditionLeft = logicSystem.true_;
        void addScope(Scope s2, immutable(Formula)* condition)
        {
            if (condition.isFalse)
                return;

            if (name in symbols)
                foreach (ref e; symbols[name].entries)
                {
                    if (e.data.type != DeclarationType.forwardScope)
                    {
                        condition = logicSystem.and(condition, e.data.condition.negated);
                    }
                }

            if (condition.isFalse)
                return;

            conditionLeft = logicSystem.and(conditionLeft, condition.negated);

            if (name in symbols)
                foreach (ref e; symbols[name].entries)
                {
                    if (e.data.type == DeclarationType.forwardScope && e.data.forwardedScope is s2)
                    {
                        e.data.condition = logicSystem.or(e.data.condition, condition);
                        symbols[name].conditionAll = logicSystem.or(symbols[name].conditionAll,
                                condition);
                        return;
                    }
                }

            auto d = new Declaration();
            d.type = DeclarationType.forwardScope;
            d.forwardedScope = s2;

            if (name !in symbols)
                symbols[name] = new DeclarationSet(name, this);
            d.condition = condition;
            symbols[name].addNew(d, logicSystem, false);
        }

        foreach (s2; extraParentScopes.entries)
        {
            if (name in s2.data.scope_.symbols)
            {
                auto x = &s2.data.scope_.symbols[name];
                immutable(Formula)* condition = logicSystem.false_;

                foreach (e2; x.entries)
                {
                    if (e2.data.type == DeclarationType.forwardScope
                            && e2.data.forwardedScope is s2.data.scope_.parentScope)
                        continue;
                    condition = logicSystem.or(condition, logicSystem.and(conditionLeft,
                            logicSystem.and(s2.condition, e2.condition)));
                }
                addScope(s2.data.scope_, condition);
            }
        }
        if (name in parentScope.symbols)
        {
            auto x = &parentScope.symbols[name];
            immutable(Formula)* condition = logicSystem.and(conditionLeft, x.conditionAll);
            if (condition.isFalse)
                return;

            addScope(parentScope, condition);
        }
    }

    DeclarationSet[string] symbols;
    final DeclarationSet getDeclarationSet(string name, LogicSystem logicSystem)
    {
        realizeForwardScope(name, logicSystem);
        if (name !in symbols)
            symbols[name] = new DeclarationSet(name, this);
        return symbols[name];
    }

    final DeclarationSet.Entry[] symbolEntries(string name)
    {
        auto x = name in symbols;
        if (x)
            return x.entries;
        return [];
    }

    final void addDeclaration(string name, immutable(Formula)* condition,
            Declaration decl, LogicSystem logicSystem)
    {
        auto ds = getDeclarationSet(name, logicSystem);
        foreach (ref e; ds.entries)
        {
            if (e.data.type == DeclarationType.forwardScope)
                e.condition = logicSystem.and(e.condition, logicSystem.not(condition));
        }
        decl.condition = condition;
        ds.addNew(decl, logicSystem, true);
    }

    final void updateDeclarationCondition(string name,
            immutable(Formula)* condition, Declaration decl, LogicSystem logicSystem)
    {
        auto ds = getDeclarationSet(name, logicSystem);
        foreach (ref e; ds.entries)
        {
            if (e.data.type == DeclarationType.forwardScope)
                e.condition = logicSystem.and(e.condition, logicSystem.not(condition));
        }
        ds.updateCondition(decl, condition, logicSystem, true);
    }

    ConditionMap!string className;

    override string toString()
    {
        string r;
        if (parentScope !is null)
        {
            r = parentScope.toString;
            r ~= " # ";
        }
        if (tree.isValid)
            r ~= "Scope " ~ tree.name ~ " " ~ locationStr(tree.start);
        else if (parentScope is null)
            r ~= "Scope null";
        else
            r ~= "Scope namespace " ~ className.entries[0].data;
        return r;
    }
}

enum DeclarationType
{
    none,
    varOrFunc,
    type, // struct / class / enum / union / typedef
    forwardScope,
    macro_,
    macroParam,
    comment,
    namespace,
    namespaceBegin,
    namespaceEnd,
    builtin, // Not real declarations
    dummy
}

enum DeclarationFlags
{
    none = 0,
    typedef_ = 1,
    function_ = 2,
    forward = 4,
    enumerator = 8,
    static_ = 0x10,
    extern_ = 0x20,
    template_ = 0x40,
    virtual = 0x80,
    override_ = 0x100,
    final_ = 0x200,
    friend = 0x400,
    abstract_ = 0x800,
    inline = 0x1000,
    constExpr = 0x2000,
    templateSpecialization = 0x4000,
}

struct DeclarationKey
{
    DeclarationType type;
    Tree tree;
    Tree declaratorTree;
    DeclarationFlags flags;
    byte bitfieldSize;
    Scope scope_;
    string name;
}

class Declaration
{
    DeclarationKey key;
    alias key this;
    DeclarationSet declarationSet;
    QualType type2;
    QualType declaredType;
    Scope forwardedScope;
    LocationRangeX location;
    immutable(Formula)* condition;
    ConditionMap!Declaration realDeclaration;
    ConditionMap!(BitFieldInfo) bitFieldInfo;
    bool isRedundant;
}

struct BitFieldInfo
{
    string dataName;
    size_t firstBit;
    size_t length;
    size_t wholeLength;
}

enum AccessSpecifier
{
    none = 0,
    private_ = 1,
    public_ = 2,
    protected_ = 4,
    qtSlot = 8,
    qtSignal = 16,
    qtInvokable = 32,
    qtScriptable = 64,
}

Scope createScope(Tree tree, Scope parentScope,
        immutable(Formula)* scopeCondition, LogicSystem logicSystem)
{
    Scope r = new Scope(tree, scopeCondition);
    createScope(r, parentScope, logicSystem);
    return r;
}

Scope createScope(Scope r, Scope parentScope, LogicSystem logicSystem)
{
    if (r.initialized)
    {
        assert(r.parentScope is parentScope);
        return r;
    }
    assert(!r.initialized);
    r.parentScope = parentScope;
    r.initialized = true;
    return r;
}

enum LookupNameFlags
{
    none = 0,
    followForwardScopes = 1,
    strictCondition = 2,
    onlyExtraParents = 4
}

Declaration[] lookupName(string name, Scope s, ref IteratePPVersions ppVersion,
        LookupNameFlags flags)
{
    if (s is null)
        return [];

    if (ppVersion.condition.isFalse)
        return [];

    bool onlyExtraParents = (flags & LookupNameFlags.onlyExtraParents) != 0;

    auto tableEntry = name in s.symbols;
    if ((flags & LookupNameFlags.followForwardScopes) == 0 && tableEntry is null)
        return [];
    while (tableEntry is null)
    {
        if (s.extraParentScopes.entries.length)
        {
            break;
        }
        s = s.parentScope;
        if (s is null)
            return [];
        tableEntry = name in s.symbols;
    }

    s.realizeForwardScope(name, ppVersion.logicSystem);
    tableEntry = name in s.symbols;
    if (tableEntry is null)
        return [];

    while (true)
    {
        ConditionMap!Declaration declsNonForward;
        ConditionMap!Scope forwardScopes;

        foreach (e; tableEntry.entries)
        {
            auto condition2 = ppVersion.logicSystem.and(ppVersion.condition, e.condition);
            if (condition2.isFalse)
                continue;
            if (e.data.type == DeclarationType.forwardScope)
            {
                if (flags & LookupNameFlags.followForwardScopes)
                {
                    if (!onlyExtraParents || e.data.forwardedScope !is s.parentScope)
                        forwardScopes.add(condition2, e.data.forwardedScope,
                                ppVersion.logicSystem);
                }
            }
            else
                declsNonForward.add(condition2, e.data, ppVersion.logicSystem);
        }

        bool useForward;

        if (forwardScopes.entries.length && declsNonForward.entries.length)
            useForward = ppVersion.combination.next(2) == 1;
        else if (forwardScopes.entries.length)
            useForward = true;

        if (useForward)
        {
            ppVersion.condition = forwardScopes.conditionAll;

            Scope nextScope = forwardScopes.choose(ppVersion);
            if (nextScope !is s.parentScope)
                onlyExtraParents = true;
            s = nextScope;
            tableEntry = name in s.symbols;
            continue;
        }
        else
        {
            if (declsNonForward.entries.length == 0)
                return [];

            ppVersion.condition = declsNonForward.conditionAll;
            immutable(Formula)*[] formulas = [];

            if (flags & LookupNameFlags.strictCondition)
            {
                formulas = [ppVersion.condition];
                void addFormula(immutable(Formula)* f)
                {
                    foreach (i, f2; formulas)
                    {
                        if (f is f2)
                            return;
                    }

                    foreach (i, f2; formulas)
                    {
                        auto a1 = ppVersion.logicSystem.and(f2, f);
                        auto a2 = ppVersion.logicSystem.and(f2, f.negated);
                        if (a1 !is ppVersion.logicSystem.false_
                                && a2 !is ppVersion.logicSystem.false_)
                        {
                            formulas[i] = a1;
                            formulas ~= a2;
                        }
                    }
                }

                foreach (e; declsNonForward.entries)
                    addFormula(e.condition);
            }
            else
            {
                formulas ~= declsNonForward.conditionAll;
            }

            ppVersion.condition = formulas[ppVersion.combination.next(cast(uint) formulas.length)];

            typeof(declsNonForward.entries[0])[] possible;
            foreach (e; declsNonForward.entries)
            {
                if (ppVersion.logicSystem.and(ppVersion.condition,
                        e.condition) !is ppVersion.logicSystem.false_)
                {
                    possible ~= e;
                }
            }

            if (possible.length == 0)
                return [];

            Declaration[] r;
            r.length = possible.length;
            foreach (i, e; possible)
                r[i] = e.data;

            r.sort!((a, b) => (a.flags & DeclarationFlags.typedef_) != 0
                    && (b.flags & DeclarationFlags.typedef_) == 0);

            return r;
        }
    }
}
