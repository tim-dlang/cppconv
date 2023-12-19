
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.runcppcommon;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
public import cppconv.locationstack;
import cppconv.logic;
import cppconv.mergedfile;
import dparsergen.core.nodetype;
import cppconv.codewriter;
import std.array;
import std.conv;
import std.stdio;
import std.string;

void parseTreeToCodeTerminal(T)(ref CodeWriter code, string name)
{
    if (name == "{")
    {
        if (code.inLine)
            code.writeln();
        code.writeln(name).incIndent;
    }
    else if (name == "}")
    {
        if (code.inLine)
            code.writeln();
        if (code.indent)
            code.decIndent();
        code.writeln(name);
    }
    else if (name.startsWith("@#"))
    {
        if (code.inLine)
            code.writeln();
        code.writeln(name);
    }
    else
    {
        if (name.length)
        {
            if (code.inLine && code.data[$ - 1] != ' '
                    && !code.data.endsWith("(") && name != ")" && name != "," && name != ";")
                code.write(" ");
            code.write(name);
        }
    }
}

void parseTreeToCode(T)(ref CodeWriter code, T tree, LogicSystem logicSystem,
        immutable(Formula)* condition, bool treeHasWhitespace = false, bool oneVersion = false)
{
    alias Location = typeof(() { return tree.start; }());
    if (!tree.isValid)
        return;

    size_t oldIndent = code.indent;
    scope (exit)
        if (tree.nodeType != NodeType.token)
            assert(oldIndent == code.indent, text(tree, "  ",
                    locationStr(tree.start), "  ", locationStr(tree.childs[0].start)));

    if (tree.nodeType == NodeType.token)
    {
        if (treeHasWhitespace || (tree.start.context !is null
                && tree.start.context.isPreprocLocation))
        {
            code.write(tree.content);
            return;
        }
        string name = tree.content.strip;
        parseTreeToCodeTerminal!T(code, name);
        if (name == ";")
            code.writeln();
    }
    else if (tree.nodeType == NodeType.merged)
    {
        if (oneVersion)
        {
            parseTreeToCode(code, tree.childs[0], logicSystem, condition,
                    treeHasWhitespace, oneVersion);
        }
        else
        {
            code.write("#{");
            foreach (i, c; tree.childs)
            {
                if (i)
                    code.write("#|");
                parseTreeToCode(code, c, logicSystem, condition, treeHasWhitespace, oneVersion);
            }
            if (code.inLine)
                code.write("#}");
            else
                code.writeln("#}");
        }
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);
        if (oneVersion)
        {
            size_t index = size_t.max;
            foreach (i; 0 .. ctree.conditions.length)
            {
                if (ctree.conditions[i].evaluate!((n, type) => false))
                {
                    assert(index == size_t.max);
                    index = i;
                }
            }
            assert(index != size_t.max);

            parseTreeToCode(code, ctree.childs[index], logicSystem, condition,
                    treeHasWhitespace, oneVersion);
        }
        else
        {
            foreach (i; 0 .. ctree.conditions.length)
            {
                auto simplified = logicSystem.removeRedundant(ctree.conditions[i], condition);
                if (code.inLine)
                    code.writeln();
                if (i == 0)
                {
                    if (simplified.type == LogicSystem.FormulaType.literal
                            && simplified.isSimple && simplified.data.name.startsWith("defined("))
                        code.writeln("#ifdef ", simplified.data.name[8 .. $ - 1]);
                    else if (ctree.conditions[i].type == LogicSystem.FormulaType.notLiteral
                            && simplified.isSimple && simplified.data.name.startsWith("defined("))
                        code.writeln("#ifndef ", simplified.data.name[8 .. $ - 1]);
                    else
                        code.writeln("#if ", simplified.toString);
                }
                else if (i < ctree.conditions.length - 1)
                    code.writeln("#elif ", simplified.toString);
                else
                    code.writeln("#else");
                code.incIndent;
                parseTreeToCode(code, ctree.childs[i], logicSystem,
                        ctree.conditions[i], treeHasWhitespace, oneVersion);
                code.decIndent;
            }
            if (code.inLine)
                code.writeln();
            code.writeln("#endif");
        }
    }
    else
    {
        if (tree.nonterminalID == nonterminalIDFor!"LinkageSpecificationEnd")
            code.incIndent;
        if (tree.name.startsWith("PP") && code.inLine)
            code.writeln();
        foreach (c; tree.childs)
        {
            parseTreeToCode(code, c, logicSystem, condition, treeHasWhitespace, oneVersion);
        }
        if (tree.name.startsWith("PP") && code.inLine)
            code.writeln();
        if (tree.nonterminalID == nonterminalIDFor!"LinkageSpecificationBegin")
            code.decIndent;
    }
}

struct CacheLRU(K, V, size_t size, alias F)
{
    static struct Entry
    {
        K key;
        V value;
        size_t age;
    }

    Entry[size] entries;

    V get(K key)
    {
        size_t minAge = size_t.max;
        size_t maxAge = 0;
        foreach (i, ref e; entries)
        {
            if (e.key != K.init)
            {
                if (minAge < e.age)
                    minAge = e.age;
                if (maxAge > e.age)
                    maxAge = e.age;
            }
        }

        foreach (i, ref e; entries)
        {
            if (key == e.key)
            {
                foreach (i2, ref e2; entries)
                {
                    e.age = e.age - minAge + 1;
                }
                e.age = 0;
                return e.value;
            }
        }
        foreach (i, ref e; entries)
        {
            if (maxAge == e.age)
            {
                foreach (i2, ref e2; entries)
                {
                    e.age = e.age - minAge + 1;
                }
                e.age = 0;
                e.key = key;
                e.value = F(key);
                return e.value;
            }
        }
        assert(false);
    }
}
