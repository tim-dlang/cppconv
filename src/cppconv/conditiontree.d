
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.conditiontree;
import cppconv.common;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.locationstack;
import cppconv.logic;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.parsestackelem;
import std.algorithm;
import std.array;

enum CONDITION_TREE_NONTERMINAL_ID = 20001;
enum CONDITION_TREE_PRODUCTION_ID = 20002;

immutable ConditionTreeAllNonterminals = [
    immutable(Nonterminal)("#PPIf", NonterminalFlags.nonterminal, [],
            [CONDITION_TREE_NONTERMINAL_ID]),
];

immutable ConditionTreeAllProductions = [
    immutable(Production)(immutable(NonterminalID)(CONDITION_TREE_NONTERMINAL_ID)),
];

immutable GrammarInfo conditionTreeGrammarInfo = immutable(GrammarInfo)(0, CONDITION_TREE_NONTERMINAL_ID,
        CONDITION_TREE_PRODUCTION_ID, [], ConditionTreeAllNonterminals,
        ConditionTreeAllProductions);

alias ConditionTree = ConditionTreeStruct*;
struct ConditionTreeStruct
{
    CppParseTreeStruct base;
    alias Tree = CppParseTree;
    immutable(Formula)*[] conditions;

    inout(CppParseTree) toTree() inout
    {
        return inout(CppParseTree)(&this.base);
    }

    inout(Tree)[] childs() inout
    {
        return toTree.childs;
    }

    this(Tree[] childs, immutable(Formula)*[] conditions, string name)
    {
        assert(childs.length > 0);
        assert(name.startsWith("#PP"));
        name = "#PPIf";
        assert(childs.length == conditions.length);
        this.conditions = conditions;

        Location nonterminalStart = Location.invalid;
        foreach (l; 0 .. childs.length)
            if (childs[l].isValid)
                nonterminalStart = minLoc(nonterminalStart, childs[l].start);
        Location nonterminalEnd = Location.invalid;
        foreach (l; 0 .. childs.length)
            if (childs[l].isValid)
                nonterminalEnd = maxLoc(nonterminalEnd, childs[l].end);

        base = CppParseTreeStruct(name, CONDITION_TREE_NONTERMINAL_ID, CONDITION_TREE_PRODUCTION_ID,
                NodeType.nonterminal, childs);
        base.grammarInfo = &conditionTreeGrammarInfo;
        base.location.setStartEnd(nonterminalStart, nonterminalEnd);
    }
}

auto toConditionTree(Tree)(Tree t)
{
    static if (is(Tree == CppParseTree))
        return cast(ConditionTree) t.this_;
    else static if (is(Tree : const(CppParseTree)))
        return cast(const(ConditionTree)) t.this_;
    else
        static assert(false);
}

struct MergedTreeData
{
    immutable(Formula)*[] conditions;
    immutable(Formula)* mergedCondition;
}

struct IteratePPVersions
{
    IterateCombination combination;
    LogicSystem logicSystem;
    immutable(Formula)* condition;
    immutable(Formula)* instanceCondition;
    MergedTreeData[const(CppParseTree)] mergedTreeDatas;

    CppParseTree chooseChild(CppParseTree tree)
    {
        immutable(Formula)*[] conditions;
        immutable(Formula)* mergedCondition = logicSystem.false_;
        if (tree.nodeType == NodeType.merged && tree in mergedTreeDatas)
        {
            auto mdata = &mergedTreeDatas[tree];
            mergedCondition = mdata.mergedCondition;
            if (instanceCondition !is null)
                mergedCondition = replaceIncludeInstanceCondition(mergedCondition,
                        instanceCondition, logicSystem);
            conditions = mdata.conditions;
        }
        else
        {
            auto ctree = tree.toConditionTree;
            assert(ctree !is null);
            conditions = ctree.conditions;
        }
        assert(conditions.length == tree.childs.length);

        with (logicSystem)
        {
            size_t[] possibleChilds;

            size_t index = size_t.max;
            foreach (i; 0 .. conditions.length)
            {
                auto subTreeCondition = conditions[i];
                if (instanceCondition !is null)
                    subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                            instanceCondition, logicSystem);

                if (and(or(subTreeCondition, and(mergedCondition,
                        literal("#merged"))), condition) !is false_)
                {
                    possibleChilds ~= i;
                }
            }

            if (possibleChilds.length == 0)
                return CppParseTree.init;

            if (possibleChilds.length == 1)
            {
                auto x = tree.childs[possibleChilds[0]];
                return x;
            }

            size_t selected = possibleChilds[combination.next(cast(uint)$)];

            CppParseTree treeX;
            if (tree.childs[selected].isValid)
                treeX = tree.childs[selected];

            condition = and(or(conditions[selected], and(mergedCondition,
                    literal("#merged"))), condition);
            return treeX;
        }
    }

    CppParseTree chooseTree(CppParseTree tree)
    {
        if (!tree.isValid)
            return tree;
        if (tree.nodeType.among(NodeType.nonterminal, NodeType.merged)
                && (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                    || (tree.nodeType == NodeType.merged && tree in mergedTreeDatas)))
        {
            return chooseChild(tree);
        }
        return tree;
    }
}

auto iteratePPVersions(alias F, P...)(CppParseTree tree,
        ref IteratePPVersions ppVersion, auto ref P params)
{
    alias R = typeof(F(tree, ppVersion, params));
    if (!tree.isValid)
    {
        static if (is(R == void))
            return;
        else
            return R.init;
    }

    if ((tree.nodeType == NodeType.nonterminal && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            || (tree.nodeType == NodeType.merged && tree in ppVersion.mergedTreeDatas))
    {
        return iteratePPVersions!(F, P)(ppVersion.chooseChild(tree), ppVersion, params);
    }
    else
    {
        return F(tree, ppVersion, params);
    }
}

bool isInCorrectVersion(ref IteratePPVersions ppVersion, immutable(Formula)* condition)
{
    with (ppVersion.logicSystem)
    {
        if (!and(ppVersion.condition, condition).isFalse
                && !and(ppVersion.condition, condition.negated).isFalse)
        {
            if (ppVersion.combination.next(2))
            {
                ppVersion.condition = and(ppVersion.condition, condition);
                return true;
            }
            else
            {
                ppVersion.condition = and(ppVersion.condition, condition.negated);
                return false;
            }
        }
        else if (!and(ppVersion.condition, condition).isFalse)
        {
            return true;
        }
        else
        {
            return false;
        }
    }
}

struct ConditionMap(T)
{
    static struct Entry
    {
        immutable(Formula)* condition;
        T data;
    }

    ArrayL!Entry entries;
    immutable(Formula)* conditionAll;
    size_t add(immutable(Formula)* condition, T data, LogicSystem logicSystem, size_t startIndex = 0)
    {
        if (conditionAll is null)
            conditionAll = condition;
        else
            conditionAll = logicSystem.or(conditionAll, condition);
        foreach (i, ref x; entries.toSlice)
        {
            if (i < startIndex)
                continue;
            if (x.data == data)
            {
                x.condition = logicSystem.simplify(logicSystem.distributeOrSimple(x.condition,
                        condition));
                return i;
            }
        }
        entries ~= Entry(condition, data);
        return entries.length - 1;
    }

    void addReplace(immutable(Formula)* condition, T data,
            LogicSystem logicSystem, bool allowReuse = false)
    {
        if (conditionAll is null)
            conditionAll = condition;
        else
            conditionAll = logicSystem.or(conditionAll, condition);
        bool found;
        size_t reusable = size_t.max;
        foreach (i, ref x; entries.toSlice)
        {
            if (x.data == data)
            {
                x.condition = logicSystem.or(x.condition, condition);
                found = true;
            }
            else
            {
                x.condition = logicSystem.and(x.condition, condition.negated);
            }
            if (x.condition.isFalse)
                reusable = i;
        }
        if (!found)
        {
            if (!allowReuse || reusable == size_t.max)
                entries ~= Entry(condition, data);
            else
                entries[reusable] = Entry(condition, data);
        }
    }

    void addNew(immutable(Formula)* condition, T data, LogicSystem logicSystem)
    {
        if (conditionAll is null)
            conditionAll = condition;
        else
            conditionAll = logicSystem.or(conditionAll, condition);
        entries ~= Entry(condition, data);
    }

    T choose(ref IteratePPVersions ppVersion)
    {
        if (conditionAll is null)
            conditionAll = ppVersion.logicSystem.false_;
        string declName;
        size_t num;
        foreach (ref e; entries.toSlice)
        {
            if (!ppVersion.logicSystem.and(ppVersion.condition, e.condition).isFalse)
                num++;
        }
        if (num == 0 || !ppVersion.logicSystem.and(ppVersion.condition,
                conditionAll.negated).isFalse)
            num++;

        auto chosen = ppVersion.combination.next(cast(uint) num);

        size_t i;
        foreach (ref e; entries.toSlice)
        {
            if (!ppVersion.logicSystem.and(ppVersion.condition, e.condition).isFalse)
            {
                if (chosen == i)
                {
                    ppVersion.condition = ppVersion.logicSystem.and(ppVersion.condition,
                            e.condition);
                    return e.data;
                }
                i++;
            }
        }
        ppVersion.condition = ppVersion.logicSystem.and(ppVersion.condition, conditionAll.negated);
        return T.init;
    }

    void removeFalseEntries()
    {
        if (entries.length <= 1)
            return;
        size_t i;
        foreach (e; entries.toSlice)
        {
            if (e.condition.isFalse)
                continue;
            entries[i] = e;
            i++;
        }
        entries.length = i;
    }
}

void addCombine(alias F, T)(ref ConditionMap!T conditionMap, immutable(Formula)* condition, T data, LogicSystem logicSystem)
{
    if (conditionMap.conditionAll is null)
        conditionMap.conditionAll = condition;
    else
        conditionMap.conditionAll = logicSystem.or(conditionMap.conditionAll, condition);
    for (size_t i = 0; i < conditionMap.entries.length; i++)
    {
        if (logicSystem.and(conditionMap.entries[i].condition, condition).isFalse)
            continue;
        if (logicSystem.and(conditionMap.entries[i].condition, condition.negated).isFalse)
        {
            conditionMap.entries[i].data = F(conditionMap.entries[i].data, data);
        }
        else
        {
            conditionMap.entries ~= conditionMap.Entry(logicSystem.and(conditionMap.entries[i].condition,
                    condition), F(conditionMap.entries[i].data, data));
            conditionMap.entries[i].condition = logicSystem.and(conditionMap.entries[i].condition, condition.negated);
        }
        condition = logicSystem.and(condition, conditionMap.entries[i].condition.negated);
    }
    if (!condition.isFalse)
    {
        conditionMap.entries ~= conditionMap.Entry(condition, data);
    }
}

void mergeConditionMaps(alias F, T)(ref ConditionMap!T lhs, ref ConditionMap!T other,
        immutable(Formula)* condition, immutable(Formula)* contextCondition,
        LogicSystem logicSystem)
{
    static Appender!(bool[]) app;
    scope (exit)
        app.clear();
    foreach (ref e; lhs.entries)
        app.put(false);
    foreach (ref o; other.entries)
    {
        auto data = F(o.data);
        auto condition2 = logicSystem.removeRedundant(o.condition, contextCondition);
        bool found;
        foreach (i, ref e; lhs.entries)
        {
            if (e.data == data)
            {
                if (e.condition !is condition2)
                    e.condition = logicSystem.or(logicSystem.and(e.condition,
                            condition.negated), logicSystem.and(condition2, condition));
                assert(app.data[i] == false);
                app.data[i] = true;
                found = true;
                break;
            }
        }
        if (!found)
        {
            lhs.entries ~= ConditionMap!T.Entry(logicSystem.and(condition2, condition), data);
        }
    }

    foreach (i; 0 .. app.data.length)
    {
        if (!app.data[i])
        {
            lhs.entries[i].condition = logicSystem.and(lhs.entries[i].condition, condition.negated);
        }
    }

    lhs.conditionAll = logicSystem.false_;
    foreach (ref e; lhs.entries)
        lhs.conditionAll = logicSystem.or(lhs.conditionAll, e.condition);
}

T evaluateConditionMap(alias F, T, alias C)(C!T m, T def = T.init)
{
    foreach (e; m.entries)
    {
        if (e.condition.boundEvaluate!F())
            return e.data;
    }
    return def;
}

immutable(Formula)* replaceIncludeInstanceCondition(immutable(Formula)* f,
        immutable(Formula)* instanceCondition, LogicSystem logicSystem)
{
    string instanceName;
    assert(instanceCondition.type != FormulaType.or, instanceCondition.toString);
    if (instanceCondition.type == FormulaType.and)
    {
        foreach (i, f2; instanceCondition.subFormulas)
        {
            assert(f2.type != FormulaType.and && f2.type != FormulaType.or);
            string name = f2.data.name;
            if (name.startsWith("@includetu:"))
                name = name["@includetu:".length .. $];
            else if (name.startsWith("@includex:"))
                name = name["@includex:".length .. $];
            else
                assert(false);
            if (i)
                assert(instanceName == name);
            instanceName = name;
        }
    }
    else
    {
        instanceName = instanceCondition.data.name;
        if (instanceName.startsWith("@includetu:"))
            instanceName = instanceName["@includetu:".length .. $];
        else if (instanceName.startsWith("@includex:"))
            instanceName = instanceName["@includex:".length .. $];
        else
            assert(false);
    }
    return replaceAll!((f2) {
        if (f2.type != FormulaType.and && f2.type != FormulaType.or)
        {
            string name = f2.data.name;
            if (name.startsWith("@includetu:"))
                name = name["@includetu:".length .. $];
            else if (name.startsWith("@includex:"))
                name = name["@includex:".length .. $];
            else
                name = "";
            if (name.length && instanceName == name)
            {
                auto f3 = logicSystem.and(f2, instanceCondition);
                if (f3.isFalse)
                    return logicSystem.false_;
                else
                    return logicSystem.true_;
            }
            else
                return f2;
        }
        else
            return f2;
    })(logicSystem, f);
}

CppParseTree deepCopyTree(CppParseTree tree, LogicSystem logicSystem)
{
    if (!tree.isValid)
        return CppParseTree.init;
    CppParseTree[] newChilds;
    newChilds.length = tree.childs.length;
    foreach (i, ref x; newChilds)
        x = deepCopyTree(tree.childs[i], logicSystem);

    CppParseTree r;

    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        auto ctree2 = new ConditionTreeStruct(newChilds, ctree.conditions, tree.name);
        r = ctree2.toTree;
    }
    else
    {
        r = CppParseTree(tree.isToken ? tree.content : tree.name, tree.nonterminalID,
                tree.productionID, tree.nodeType, newChilds, treeAllocator);
        r.grammarInfo = tree.grammarInfo;
    }
    r.setStartEnd(tree.start, tree.end);

    if (tree.nodeType == NodeType.nonterminal
            && tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParameterDeclarationAbstract"
            && !tree.childs[1].isValid)
    {
        auto grammarInfo = &ParserWrapper.grammarInfo;
        static foreach (i, P; ParserWrapper.allProductions)
        {
            static if (P.nonterminalID != NonterminalID.invalid
                    && ParserWrapper.allNonterminals[P.nonterminalID.id - ParserWrapper.startNonterminalID].name
                    == "FakeAbstractDeclarator")
            {
                auto M = ParserWrapper.allNonterminals[P.nonterminalID.id
                    - ParserWrapper.startNonterminalID];
                CppParseTree fakeDeclarator = CppParseTree(M.name, P.nonterminalID.id,
                        i + ParserWrapper.startProductionID, NodeType.nonterminal, []);
            }
        }
        fakeDeclarator.grammarInfo = grammarInfo;
        fakeDeclarator.setStartEnd(LocationX(LocationN.invalid), LocationX(LocationN.invalid));
        r.childs[1] = fakeDeclarator;
    }

    return r;
}
