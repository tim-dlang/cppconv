
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter.conditioncode;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.dwriter.declarationcode;
import cppconv.dwriter.macrodeclaration;
import cppconv.dwriter.treecode;
import cppconv.dwriter.dwriter;
import cppconv.grammarcpp;
import cppconv.preproc;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;

alias parseTreeToCodeTerminal = cppconv.dwriter.treecode.parseTreeToCodeTerminal;

struct ConditionalCodeWrapper
{
    ConditionMap!string conditionMapPrefix;
    ConditionMap!string conditionMapSuffix;
    DWriterData data;
    immutable(Formula)* firstCondition;
    immutable(Formula)* currentCondition;
    StringType currentStringType;
    bool forceExpression;
    bool active;

    enum StringType
    {
        none,
        code,
        string
    }

    this(immutable(Formula)* condition, DWriterData data)
    {
        this.data = data;
        firstCondition = condition;
        conditionMapPrefix.add(condition, "", data.semantic.logicSystem);
        conditionMapSuffix.add(condition, "", data.semantic.logicSystem);
    }

    void add(string prefix, string suffix, immutable(Formula)* condition)
    in(!active)
    {
        {
            string[] newData;
            immutable(Formula)*[] newConditions;

            foreach (ref x; conditionMapPrefix.entries)
            {
                auto data = prefix ~ x.data;
                auto condition2 = this.data.logicSystem.and(condition, x.condition);
                if (!condition2.isFalse)
                {
                    newData ~= data;
                    newConditions ~= condition2;
                }
            }
            foreach (i; 0 .. newData.length)
            {
                conditionMapPrefix.addReplace(newConditions[i], newData[i], data.logicSystem);
            }
        }
        {
            string[] newData;
            immutable(Formula)*[] newConditions;

            foreach (ref x; conditionMapSuffix.entries)
            {
                auto data = x.data ~ suffix;
                auto condition2 = this.data.logicSystem.and(condition, x.condition);
                if (!condition2.isFalse)
                {
                    newData ~= data;
                    newConditions ~= condition2;
                }
            }
            foreach (i; 0 .. newData.length)
            {
                conditionMapSuffix.addReplace(newConditions[i], newData[i], data.logicSystem);
            }
        }
    }

    bool alwaysUseMixin;

    static bool isTreeArray(Tree tree)
    {
        if (!tree.isValid)
            return false;
        if (tree.nodeType == NodeType.array)
            return true;
        if (tree.nodeType == NodeType.nonterminal
                && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            foreach (c; tree.childs)
                if (isTreeArray(c))
                    return true;
        if (tree.nodeType == NodeType.merged)
            foreach (i, c; tree.childs)
                if (isTreeArray(c))
                    return true;
        return false;
    }

    static bool isTreeAnyTerminal(Tree tree)
    {
        if (!tree.isValid)
            return false;
        if (tree.nodeType == NodeType.token)
            return true;
        if (tree.nodeType == NodeType.nonterminal
                && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            foreach (c; tree.childs)
                if (isTreeAnyTerminal(c))
                    return true;
        if (tree.nodeType == NodeType.merged)
            foreach (i, c; tree.childs)
                if (isTreeAnyTerminal(c))
                    return true;
        return false;
    }

    bool allowNonArrayPPIf;
    bool allowNonArrayPPIfSet;

    bool isConditionalMergedTree(Tree tree)
    {
        if (tree.nodeType == NodeType.merged)
        {
            size_t numPossible;
            auto mdata = &data.semantic.mergedTreeData(tree);
            if (!mdata.mergedCondition.isFalse)
                numPossible++;
            foreach (i, condition; mdata.conditions)
                if (!condition.isFalse)
                    numPossible++;

            if (numPossible > 1)
                return true;
        }
        return false;
    }

    void checkTree(Tree tree, bool allowNonArrayPPIf,
        scope bool delegate(Tree) shouldDescent = null)
    in(!active)
    {
        if (allowNonArrayPPIfSet)
            assert(this.allowNonArrayPPIf == allowNonArrayPPIf);
        this.allowNonArrayPPIf = allowNonArrayPPIf;
        allowNonArrayPPIfSet = true;
        if (!allowNonArrayPPIf || isTreeArray(tree) || isTreeAnyTerminal(tree))
        {
            if (tree.nodeType == NodeType.nonterminal && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                alwaysUseMixin = true;
            }
            if (isConditionalMergedTree(tree))
            {
                alwaysUseMixin = true;
            }
        }
        if (tree.nodeType == NodeType.array
            || (tree.nodeType == NodeType.nonterminal && shouldDescent !is null && shouldDescent(tree)))
        {
            foreach (c; tree.childs)
                checkTree(c, allowNonArrayPPIf, shouldDescent);
        }
    }

    void checkTree(Tree[] trees, bool allowNonArrayPPIf,
        scope bool delegate(Tree) shouldDescent = null)
    in(!active)
    {
        foreach (c; trees)
            checkTree(c, allowNonArrayPPIf, shouldDescent);
    }

    void changeCurrentCondition(ref CodeWriter code,
            immutable(Formula)* condition, StringType stringType)
    in(active)
    {
        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
            return;
        if (condition !is currentCondition || stringType != currentStringType)
        {
            if (currentStringType != StringType.none)
            {
                if (currentStringType == StringType.code)
                {
                    if (code.inLine)
                        code.writeln();
                    code.write("}");
                }
                else if (currentStringType == StringType.string)
                    code.write("\"");
                if (currentCondition !is firstCondition)
                    code.write(":\"\")");
                code.writeln();
            }
            if (stringType != StringType.none)
            {
                immutable(Formula)* simplified = data.logicSystem.removeRedundant(condition,
                        firstCondition);
                simplified = removeLocationInstanceConditions(simplified,
                        data.logicSystem, data.mergedFileByName);
                code.write("~ ");
                data.afterStringLiteral = false;
                if (condition !is firstCondition)
                    code.write("(", conditionToDCode(simplified, data), " ? ");
                if (stringType == StringType.code)
                    code.writeln("q{");
                else if (stringType == StringType.string)
                    code.write("\"");
            }

            currentCondition = condition;
            currentStringType = stringType;
        }
    }

    void begin(ref CodeWriter code, immutable(Formula)* condition)
    in(!active)
    {
        active = true;

        size_t outI;
        foreach (i, e; conditionMapPrefix.entries)
        {
            if (!e.condition.isFalse)
            {
                conditionMapPrefix.entries[outI] = e;
                outI++;
            }
        }
        conditionMapPrefix.entries.length = outI;

        outI = 0;
        foreach (i, e; conditionMapSuffix.entries)
        {
            if (!e.condition.isFalse)
            {
                conditionMapSuffix.entries[outI] = e;
                outI++;
            }
        }
        conditionMapSuffix.entries.length = outI;

        if (conditionMapPrefix.entries.length == 0)
            conditionMapPrefix.add(data.logicSystem.false_, "", data.logicSystem);
        if (conditionMapSuffix.entries.length == 0)
            conditionMapSuffix.add(data.logicSystem.false_, "", data.logicSystem);

        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
        {
            parseTreeToCodeTerminal(code, conditionMapPrefix.entries[0].data);
        }
        else
        {
            alwaysUseMixin = true;
            if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                code.write(" ");
            if (forceExpression)
                code.write("(");
            code.write("mixin(");
            if (conditionMapPrefix.entries.length > 1)
            {
                bool first = true;
                foreach (i, e; conditionMapPrefix.entries)
                {
                    auto simplified = data.logicSystem.removeRedundant(data.logicSystem.and(condition,
                            e.condition), condition);
                    simplified = removeLocationInstanceConditions(simplified,
                            data.logicSystem, data.mergedFileByName);
                    if (first)
                    {
                        first = false;
                        code.write("((", conditionToDCode(simplified, data), ") ? \"");
                    }
                    else if (i < conditionMapPrefix.entries.length - 1)
                    {
                        code.write("\" : (", conditionToDCode(simplified, data), ") ? \"");
                    }
                    else
                    {
                        code.write("\" : \"");
                    }
                    code.write(e.data.escapeDString);
                }
                code.write("\"");
                code.write(")");
                code.write(" ~ ");
            }
            else if (conditionMapPrefix.entries[0].data.length)
            {
                code.write("\"", conditionMapPrefix.entries[0].data.escapeDString, "\" ~ ");
            }

            code.write("q{");
            currentCondition = firstCondition;
            currentStringType = StringType.code;
        }
    }

    void end(ref CodeWriter code, immutable(Formula)* condition)
    in(active)
    {
        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
        {
            parseTreeToCodeTerminal(code, conditionMapSuffix.entries[0].data);
        }
        else
        {
            changeCurrentCondition(code, null, StringType.none);

            if (conditionMapSuffix.entries.length > 1)
            {
                code.write(" ~ ");
                bool first = true;
                foreach (i, e; conditionMapSuffix.entries)
                {
                    auto simplified = data.logicSystem.removeRedundant(data.logicSystem.and(condition,
                            e.condition), condition);
                    simplified = removeLocationInstanceConditions(simplified,
                            data.logicSystem, data.mergedFileByName);
                    if (first)
                    {
                        first = false;
                        code.write("((", conditionToDCode(simplified, data), ") ? \"");
                    }
                    else if (i < conditionMapSuffix.entries.length - 1)
                    {
                        code.write("\" : (", conditionToDCode(simplified, data), ") ? \"");
                    }
                    else
                    {
                        code.write("\" : \"");
                    }
                    code.write(e.data.escapeDString);
                }
                code.write("\"");
                code.write(")");
            }
            else if (conditionMapSuffix.entries[0].data.length)
            {
                code.write(" ~ \"", conditionMapSuffix.entries[0].data.escapeDString, "\"");
            }

            code.write(")");
            if (forceExpression)
                code.write(")");
        }
        active = false;
    }

    void writeTree(ref CodeWriter code,
            scope void delegate(Tree, immutable(Formula)*) F,
            Tree tree, immutable(Formula)* condition)
    in(active)
    {
        if (!tree.isValid)
            return;
        if (tree.nodeType == NodeType.nonterminal && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                && (!allowNonArrayPPIf || isTreeArray(tree) || isTreeAnyTerminal(tree)))
        {
            auto ctree = tree.toConditionTree;
            assert(ctree !is null);
            foreach (i; 0 .. ctree.conditions.length)
            {
                writeTree(code, F, ctree.childs[i],
                        data.logicSystem.and(condition, ctree.conditions[i]));
            }
        }
        else if (isConditionalMergedTree(tree))
        {
            auto mdata = &data.semantic.mergedTreeData(tree);
            foreach (i; 0 .. mdata.conditions.length)
            {
                writeTree(code, F, tree.childs[i],
                        data.logicSystem.and(condition,
                            data.logicSystem.or(
                                data.logicSystem.and(mdata.mergedCondition,
                                    data.logicSystem.literal("#merged")),
                                mdata.conditions[i])));
            }
        }
        else if (tree.nodeType == NodeType.array)
        {
            foreach (c; tree.childs)
                writeTree(code, F, c, condition);
        }
        else
        {
            changeCurrentCondition(code, condition, StringType.code);
            F(tree, condition);
        }
    }

    void writeTree(ref CodeWriter code, scope void delegate(Tree, immutable(Formula)*) F, Tree tree)
    in(active)
    {
        writeTree(code, F, tree, firstCondition);
    }

    void writeTree(ref CodeWriter code, scope void delegate(Tree,
            immutable(Formula)*) F, Tree[] trees)
    in(active)
    {
        foreach (c; trees)
            writeTree(code, F, c);
    }

    void writeString(ref CodeWriter code, string s, immutable(Formula)* condition = null)
    in(active)
    {
        if (condition is null)
            condition = firstCondition;
        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
        {
        }
        else
            changeCurrentCondition(code, condition, StringType.string);
        code.write(s);
    }

    void writeCode(ref CodeWriter code, string s, immutable(Formula)* condition = null)
    in(active)
    {
        if (condition is null)
            condition = firstCondition;
        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
        {
        }
        else
            changeCurrentCondition(code, condition, StringType.code);
        code.write(s);
    }
}

void conditionToDCode(O)(ref O outRange, immutable(Formula)* condition, DWriterData data)
{
    if (condition.type == FormulaType.and)
    {
        if (condition.subFormulasLength == 0)
        {
            outRange.put("true");
            return;
        }
        outRange.put("(");
        foreach (i, f; condition.subFormulas)
        {
            if (i)
                outRange.put(" && ");
            conditionToDCode!O(outRange, f, data);
        }
        outRange.put(")");
    }
    else if (condition.type == FormulaType.or)
    {
        if (condition.subFormulasLength == 0)
        {
            outRange.put("false");
            return;
        }
        outRange.put("(");
        foreach (i, f; condition.subFormulas)
        {
            if (i)
                outRange.put(" || ");
            conditionToDCode!O(outRange, f, data);
        }
        outRange.put(")");
    }
    else if (condition in data.mergedAliasMap)
    {
        outRange.put("versionIsSet!(\"" ~ data.mergedAliasMap[condition] ~ "\")");
    }
    else if (condition.negated in data.mergedAliasMap)
    {
        outRange.put("!");
        outRange.put("versionIsSet!(\"" ~ data.mergedAliasMap[condition.negated] ~ "\")");
    }
    else
    {
        bool isBound = condition.type == FormulaType.greaterEq || condition.type == FormulaType.less;
        string name = condition.data.name;
        bool useVersion;
        if (name.startsWith("defined("))
        {
            name = name["defined(".length .. $ - 1];
            if (name in data.options.versionReplacements)
                useVersion = true;
            else
                name = "defined!\"" ~ name ~ "\"";
        }
        else if (name.startsWith("__has_include("))
        {
            name = "__has_include!" ~ name["__has_include(".length .. $ - 1] ~ "";
        }
        else if (name in data.options.versionReplacements)
            useVersion = true;
        else
        {
            string name2;
            while (name.length)
            {
                if (name[0].inCharSet!"a-zA-Z0-9_")
                {
                    size_t l = 1;
                    while (l < name.length && name[l].inCharSet!"a-zA-Z0-9_")
                    {
                        l++;
                    }
                    if (name[0].inCharSet!"0-9")
                        name2 ~= name[0 .. l];
                    else if (name[0 .. l].among("QT_STRINGVIEW_LEVEL"))
                        name2 ~= name[0 .. l];
                    else
                        name2 ~= "configValue!\"" ~ name[0 .. l] ~ "\"";
                    name = name[l .. $];
                }
                else
                {
                    name2 ~= name[0];
                    name = name[1 .. $];
                }
            }
            name = name2;
        }
        if (useVersion)
        {
            bool negated = !isLiteralPositive(condition);
            string replaced = data.options.versionReplacements[name];
            if (replaced.startsWith("!"))
            {
                replaced = replaced[1 .. $];
                negated = !negated;
            }
            if (negated)
                outRange.put("!");
            outRange.put("versionIsSet!(\"" ~ replaced ~ "\")");
        }
        else if (!isBound)
        {
            if (condition.data.number == 0)
            {
                if (condition.type & 1)
                    outRange.put("!");
                outRange.put(name);
            }
            else
            {
                outRange.put(name);
                if (condition.type & 1)
                    outRange.put(" == ");
                else
                    outRange.put(" != ");
                outRange.put(text(condition.data.number));
            }
        }
        else
        {
            outRange.put(name);
            if (condition.type & 1)
                outRange.put(" < ");
            else
                outRange.put(" >= ");
            outRange.put(text(condition.data.number));
        }
    }
}

string conditionToDCode(immutable(Formula)* condition, DWriterData data)
{
    Appender!string app;
    conditionToDCode(app, condition, data);
    return app.data;
}

bool isVersionOnlyCondition(immutable(Formula)* condition, DWriterData data, bool allowAndOr = true)
{
    string[immutable(Formula)*] versionReplacementsOr = data.versionReplacementsOr;
    if (condition.type == FormulaType.or)
    {
        if (allowAndOr)
            return !!(condition in versionReplacementsOr);
        else
            return false;
    }
    else if (condition.type == FormulaType.and)
    {
        if (allowAndOr)
        {
            foreach (f; condition.subFormulas)
                if (!isVersionOnlyCondition(f, data, false))
                    return false;
            return true;
        }
        else
            return false;
    }
    else if (condition in data.mergedAliasMap)
    {
        return true;
    }
    else if (condition.negated in data.mergedAliasMap)
    {
        return true;
    }
    else
    {
        string name = condition.data.name;
        bool useVersion;
        if (name.startsWith("defined("))
        {
            name = name["defined(".length .. $ - 1];
        }
        if (name in data.options.versionReplacements)
            useVersion = true;

        return useVersion;
    }
}

bool isVersionOnlyConditionSimple(immutable(Formula)* condition, DWriterData data)
{
    string[immutable(Formula)*] versionReplacementsOr = data.versionReplacementsOr;
    if (condition.type == FormulaType.or)
    {
        return false;
    }
    else if (condition.type == FormulaType.and)
    {
        return false;
    }
    else if (condition in data.mergedAliasMap)
    {
        return true;
    }
    else if (condition.negated in data.mergedAliasMap)
    {
        return false;
    }
    else
    {
        if (!isLiteralPositive(condition))
            return false;

        string name = condition.data.name;
        bool useVersion;
        if (name.startsWith("defined("))
        {
            name = name["defined(".length .. $ - 1];
        }
        if (name in data.options.versionReplacements)
            useVersion = true;

        return useVersion;
    }
}

void versionConditionToDCode(ref CodeWriter code, immutable(Formula)* condition,
        DWriterData data, bool addNewline = true)
{
    string[immutable(Formula)*] versionReplacementsOr = data.versionReplacementsOr;
    if (condition.type == FormulaType.and)
    {
        foreach (c; condition.subFormulas)
            assert(isVersionOnlyCondition(c, data));

        bool needsNewline;

        foreach (c; condition.subFormulas)
        {
            if (c in data.mergedAliasMap)
            {
                continue;
            }
            else if (c.negated in data.mergedAliasMap)
            {
                if (needsNewline)
                    code.writeln();
                code.write("version (" ~ data.mergedAliasMap[c.negated] ~ ") {} else");
                needsNewline = true;
                continue;
            }

            string name = c.data.name;
            if (name.startsWith("defined("))
                name = name["defined(".length .. $ - 1];
            bool negated = !isLiteralPositive(c);
            string replaced = data.options.versionReplacements[name];
            if (replaced.startsWith("!"))
            {
                replaced = replaced[1 .. $];
                negated = !negated;
            }
            if (negated)
            {
                if (needsNewline)
                    code.writeln();
                code.write("version (" ~ replaced ~ ") {} else");
                needsNewline = true;
            }
        }
        foreach (c; condition.subFormulas)
        {
            if (c in data.mergedAliasMap)
            {
                if (needsNewline)
                    code.writeln();
                code.write("version (" ~ data.mergedAliasMap[c] ~ ")");
                needsNewline = true;
                continue;
            }
            else if (c.negated in data.mergedAliasMap)
            {
                continue;
            }

            string name = c.data.name;
            if (name.startsWith("defined("))
                name = name["defined(".length .. $ - 1];
            bool negated = !isLiteralPositive(c);
            string replaced = data.options.versionReplacements[name];
            if (replaced.startsWith("!"))
            {
                replaced = replaced[1 .. $];
                negated = !negated;
            }
            if (!negated)
            {
                if (needsNewline)
                    code.writeln();
                code.write("version (" ~ replaced ~ ")");
                needsNewline = true;
            }
        }
        if (needsNewline && addNewline)
            code.writeln();
        return;
    }
    else if (condition.type == FormulaType.or)
    {
        code.write("version (", versionReplacementsOr[condition], ")");
        if (addNewline)
            code.writeln();
        return;
    }
    else if (condition in data.mergedAliasMap)
    {
        code.write("version (" ~ data.mergedAliasMap[condition] ~ ")");
        if (addNewline)
            code.writeln();
        return;
    }
    else if (condition.negated in data.mergedAliasMap)
    {
        code.write("version (" ~ data.mergedAliasMap[condition.negated] ~ ") {} else");
        if (addNewline)
            code.writeln();
        return;
    }

    string name = condition.data.name;
    if (name.startsWith("defined("))
        name = name["defined(".length .. $ - 1];

    bool negated = !isLiteralPositive(condition);
    string replaced = data.options.versionReplacements[name];
    if (replaced.startsWith("!"))
    {
        replaced = replaced[1 .. $];
        negated = !negated;
    }
    assert(isVersionOnlyCondition(condition, data));
    if (!negated)
        code.write("version (" ~ replaced ~ ")");
    else
        code.write("version (" ~ replaced ~ ") {} else");
    if (addNewline)
        code.writeln();
}

void conditionTreeToDCode(T)(ref CodeWriter code, DWriterData data, Tree tree, T[] childs,
        immutable(Formula)*[] conditions, LogicSystem logicSystem, immutable(Formula)* condition,
        Scope currentScope, TreeToCodeFlags treeToCodeFlags = TreeToCodeFlags.none)
{
    auto semantic = data.semantic;
    Tree parent = getRealParent(tree, semantic);
    string commonMacro;
    foreach (i; 0 .. conditions.length)
    {
        if (!childs[i].isValid)
            continue;
        immutable(LocationContext)* locContext = childs[i].start.context;
        while (locContext !is null && locContext.prev !is tree.start.context)
        {
            locContext = locContext.prev;
        }
        if (locContext is null)
        {
            commonMacro = "";
            continue;
        }
        if (i == 0)
            commonMacro = locContext.name;
        else
        {
            if (commonMacro != locContext.name)
                commonMacro = "";
        }
    }
    if (commonMacro.length && commonMacro in data.options.macroReplacements)
    {
        if (data.sourceTokenManager.tokensLeft.data.length)
        {
            writeComments(code, data, tree.start);
            data.sourceTokenManager.collectTokens(tree.end);
        }
        parseTreeToCodeTerminal(code, data.options.macroReplacements[commonMacro]);
        return;
    }

    // Merge identical macro instances
    {
        bool afterStringLiteralBak = data.afterStringLiteral;
        size_t outI = 0;
        size_t[string] macroCodes;
        foreach (i, c; childs)
        {
            if (childs[i] in data.macroReplacement)
            {
                auto instance = data.macroReplacement[childs[i]];

                CodeWriter code2;
                writeMacroInstance(code2, data, childs[i], logicSystem.and(condition, conditions[i]), currentScope, TreeToCodeFlags.none, false);
                data.afterStringLiteral = afterStringLiteralBak;

                if (code2.data in macroCodes)
                {
                    size_t j = macroCodes[code2.data];
                    conditions[j] = logicSystem.or(conditions[j], conditions[i]);
                    continue;
                }

                macroCodes[code2.data] = outI;
            }

            conditions[outI] = conditions[i];
            childs[outI] = childs[i];
            outI++;
        }
        conditions.length = outI;
        childs.length = outI;
    }

    SourceToken[] tokensBefore;
    if (data.sourceTokenManager.tokensLeft.data.length)
        tokensBefore = data.sourceTokenManager.collectTokens(
                locationBeforeUsedMacro(tree, data, false));
    PPConditionalInfo* ppConditionalInfo;
    LocationX locLastDirective;
    foreach (x; tokensBefore)
    {
        if (x.token.nodeType != NodeType.token && x.token.name.among("PPIf", "PPIfDef", "PPIfNDef"))
        {
            if (ppConditionalInfo is null)
                ppConditionalInfo = data.sourceTokenManager.ppConditionalInfo[x.token];
            else
            {
                ppConditionalInfo = null;
                break;
            }
        }
        else if (x.token.nodeType != NodeType.token
                && x.token.name.among("PPElse", "PPElif", "PPEndif"))
        {
            ppConditionalInfo = null;
            break;
        }
    }
    if (ppConditionalInfo !is null && ppConditionalInfo.directives.length > childs.length + 1)
        ppConditionalInfo = null;
    if (ppConditionalInfo !is null)
    {
        auto tokensLeft = data.sourceTokenManager.tokensLeft.data[$ - 1];
        size_t k;
        bool good = true;
        foreach (i, c; childs)
        {
            if (i + 1 == childs.length && (!c.isValid
                    || (c.nodeType == NodeType.array && c.childs.length == 0)))
                continue;
            if (i + 1 >= ppConditionalInfo.directives.length)
            {
                good = false;
                break;
            }
            if (i)
            {
                bool found;
                while (k < tokensLeft.length && LocationX(tokensLeft[k].token.end.loc,
                        data.sourceTokenManager.locDone.context) <= c.start)
                {
                    auto x = tokensLeft[k];
                    if (x.token.nodeType != NodeType.token && x.token.name.among("PPIf",
                            "PPIfDef", "PPIfNDef", "PPElse", "PPElif", "PPEndif"))
                    {
                        if (x.token !is ppConditionalInfo.directives[i])
                        {
                            good = false;
                        }
                        found = true;
                    }
                    k++;
                }
                if (!found)
                {
                    good = false;
                }
            }
            while (k < tokensLeft.length && LocationX(tokensLeft[k].token.end.loc,
                    data.sourceTokenManager.locDone.context) <= c.end)
            {
                auto x = tokensLeft[k];
                k++;
            }
        }
        bool found;
        while (k < tokensLeft.length && LocationX(tokensLeft[k].token.end.loc,
                data.sourceTokenManager.locDone.context) <= data.nextTreeStart[tree])
        {
            auto x = tokensLeft[k];
            if (x.token.nodeType != NodeType.token && x.token.name.among("PPIf",
                    "PPIfDef", "PPIfNDef", "PPElse", "PPElif", "PPEndif"))
            {
                if (x.token !is ppConditionalInfo.directives[$ - 1])
                {
                    good = false;
                }
                found = true;
                locLastDirective = LocationX(x.token.end.loc,
                        data.sourceTokenManager.locDone.context);
            }
            k++;
        }
        if (!found)
        {
            good = false;
        }
        if (!good)
            ppConditionalInfo = null;
    }

    if (data.sourceTokenManager.tokensLeft.data.length && ppConditionalInfo is null)
    {
        writeComments(code, data, tokensBefore);
        tokensBefore = [];
    }

    size_t numPossible;
    size_t lastPossibleChild;
    bool isExpression;
    foreach (i; 0 .. conditions.length)
    {
        if (!childs[i].isValid)
            continue;
        if (isTreeExpression(childs[i], semantic))
            isExpression = true;
        // Types are handled like expressions here.
        if (parent.isValid && parent.nonterminalID.nonterminalIDAmong!("DeclSpecifierSeq", "SimpleTemplateId"))
            isExpression = true;
        if (!logicSystem.and(condition, conditions[i]).isFalse)
        {
            numPossible++;
            lastPossibleChild = i;
        }
    }
    if (numPossible == 0)
    {
        code.writeln("TODO: impossible condition tree");
        return;
    }
    assert(numPossible);
    bool needsParens;
    if (isExpression)
    {
        if (parent.isValid && parent.nonterminalID.nonterminalIDAmong!("ArrayDeclarator",
                "ExpressionStatement"))
            needsParens = true;
        if (treeToCodeFlags & TreeToCodeFlags.inStatementExpression)
            needsParens = true;
    }

    if (numPossible == 1)
    {
        if (childs[lastPossibleChild] is tree)
        {
            assert(childs[lastPossibleChild].nodeType == NodeType.merged);
            auto ctree = childs[lastPossibleChild];
            auto mdata = &semantic.mergedTreeData(ctree);
            code.write("UnresolvedMergeConflict!(q{");
            foreach (i, c; ctree.childs)
            {
                if (i)
                    code.write("},q{");
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
            bool inLine = code.inLine;
            code.write("})");
            if (tree.nodeType == NodeType.merged && tree.nonterminalID == nonterminalIDFor!"Statement")
                code.write(";");
            if (!inLine)
                code.writeln();
        }
        else
            parseTreeToDCode(code, data, childs[lastPossibleChild],
                    logicSystem.and(condition, conditions[lastPossibleChild]), currentScope);
        return;
    }

    if (data.afterStringLiteral)
        code.write("~ ");

    size_t l = 0;
    string lastLineIndent;
    string origCustomIndent = code.customIndent;
    scope (success)
        code.customIndent = origCustomIndent;
    string newCustomIndent;
    string newCustomIndent2;
    foreach (i; 0 .. conditions.length)
    {
        data.afterStringLiteral = false;
        if (logicSystem.and(condition, conditions[i]).isFalse)
            continue;
        if (i + 1 == conditions.length && (!childs[i].isValid
                || (childs[i].nodeType == NodeType.array && childs[i].childs.length == 0
                    && !(parent.isValid && parent.nonterminalID.nonterminalIDAmong!("StringLiteralSequence")))))
            continue;
        auto simplified0 = logicSystem.removeRedundant(logicSystem.and(condition,
                conditions[i]), condition);
        auto simplified = removeLocationInstanceConditions(simplified0,
                semantic.logicSystem, data.mergedFileByName);

        SourceToken[] tokensBetween;
        if (data.sourceTokenManager.tokensLeft.data.length)
            tokensBetween = i ? data.sourceTokenManager.collectTokens(
                    locationBeforeUsedMacro(childs[i], data, false)) : tokensBefore;
        CodeWriter codeAfterDirective;
        codeAfterDirective.customIndent = origCustomIndent;
        codeAfterDirective.indentStr = data.options.indent;
        if (ppConditionalInfo !is null)
        {
            size_t k;
            while (k < tokensBetween.length)
            {
                auto x = tokensBetween[k];
                if (x.token is ppConditionalInfo.directives[i])
                {
                    writeComments(code, data, tokensBetween[0 .. k]);
                    tokensBetween = tokensBetween[k + 1 .. $];
                    k = 0;
                    break;
                }
                k++;
            }
            writeComments(codeAfterDirective, data, tokensBetween);
            tokensBetween = [];
        }

        if (l == 0)
        {
            if (getLastLineIndent(codeAfterDirective.data.length
                    ? codeAfterDirective : code, lastLineIndent))
            {
                if (!isExpression || l)
                    code.writeln();
                else if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                    code.write(" ");
            }
            newCustomIndent = lastLineIndent.length ? lastLineIndent : code.customIndent;
            newCustomIndent2 = code.indentStr ~ origCustomIndent;
            if (isExpression)
            {
                newCustomIndent = code.indentStr ~ newCustomIndent;
                newCustomIndent2 = code.indentStr ~ newCustomIndent2;
            }
            code.customIndent = newCustomIndent;
            if (isExpression)
            {
                code.write(needsParens ? "(" : "", "mixin((",
                        conditionToDCode(simplified, data), ") ? q{");
                if (simplified0 !is simplified && data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
            }
            else
            {
                if ((conditions.length == 1 && isVersionOnlyCondition(simplified, data))
                        || (conditions.length == 2 && isVersionOnlyConditionSimple(simplified, data))
                        || (conditions.length == 2 && isVersionOnlyCondition(simplified, data)
                            && (!childs[1].isValid || (childs[1].nodeType == NodeType.array
                            && childs[1].childs.length == 0))))
                    versionConditionToDCode(code, simplified, data, false);
                else
                    code.write("static if (", conditionToDCode(simplified, data), ")");
                if (simplified0 !is simplified && data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
                code.writeln("{");
            }
        }
        else if (l < numPossible - 1)
        {
            if (isExpression)
            {
                code.write("} : (", conditionToDCode(simplified, data), ") ? q{");
                if (simplified0 !is simplified && data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
            }
            else
            {
                code.writeln("}");
                code.write("else static if (", conditionToDCode(simplified, data), ")");
                if (simplified0 !is simplified && data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
                code.writeln("{");
            }
        }
        else
        {
            if (isExpression)
            {
                code.write("} : q{");
                if (data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
            }
            else
            {
                code.writeln("}");
                code.write("else");
                if (data.options.addDeclComments)
                    code.write(" // ", simplified0.toString);
                code.writeln();
                code.writeln("{");
            }
        }
        if (codeAfterDirective.data.length)
        {
            code.customIndent = code.indentStr;
            code.write(codeAfterDirective.data);
        }
        else if (l == 0)
        {
            code.customIndent = newCustomIndent2;
            code.write(lastLineIndent);
        }
        code.customIndent = newCustomIndent2;

        writeComments(code, data, tokensBetween);

        if (childs[i].nodeType == NodeType.merged && childs[i] is tree)
        {
            auto mdata = &semantic.mergedTreeData(childs[i]);
            code.write("#{");
            foreach (k, c; childs[i].childs)
            {
                if (k)
                    code.write("#|");
                parseTreeToDCode(code, data, c, logicSystem.and(condition,
                        logicSystem.literal("#merged")), currentScope);
            }
            if (code.inLine)
                code.write("#}");
            else
                code.writeln("#}");
        }
        else if (childs[i].nodeType == NodeType.array && childs[i].childs.length == 0
            && parent.isValid && parent.nonterminalID.nonterminalIDAmong!("StringLiteralSequence"))
        {
            code.write("\"\"");
            data.afterStringLiteral = true;
        }
        else
            parseTreeToDCode(code, data, childs[i], logicSystem.and(condition, conditions[i]), currentScope);
        if (data.sourceTokenManager.tokensLeft.data.length
                && childs[i].isValid && childs[i].location.context !is null)
            writeComments(code, data, data.sourceTokenManager.collectTokensUntilLineEnd(childs[i].location.end, logicSystem.and(condition, conditions[i])));
        string lastLineIndentUnused;
        code.customIndent = newCustomIndent;
        if (getLastLineIndent(code, lastLineIndentUnused))
            code.writeln();
        l++;
    }
    if (ppConditionalInfo !is null)
    {
        auto tokensAfter = data.sourceTokenManager.collectTokens(locLastDirective);
        size_t k;
        while (k < tokensAfter.length)
        {
            auto x = tokensAfter[k];
            if (x.token is ppConditionalInfo.directives[$ - 1])
            {
                writeComments(code, data, tokensAfter[0 .. k]);
                tokensAfter = tokensAfter[k + 1 .. $];
                break;
            }
            k++;
        }
        writeComments(code, data, tokensAfter);
    }
    if (isExpression)
    {
        string lastLineIndentUnused;
        if (getLastLineIndent(code, lastLineIndentUnused))
            code.writeln();
        code.write("})", needsParens ? ")" : "");
    }
    else
    {
        string lastLineIndentUnused;
        if (getLastLineIndent(code, lastLineIndentUnused))
            code.writeln();
        code.writeln("}");
    }
}
