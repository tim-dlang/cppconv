
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter.treecode;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.dwriter.declarationcode;
import cppconv.dwriter.declarationselection;
import cppconv.dwriter.macrodeclaration;
import cppconv.dwriter.typecode;
import cppconv.dwriter.dwriter;
import cppconv.dwriter.conditioncode;
import cppconv.filecache;
import cppconv.grammarcpp;
import cppconv.mergedfile;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.string;

void parseTreeToCodeTerminal(ref CodeWriter code, string name)
{
    if (name.startsWith("@#"))
    {
        if (code.inLine)
            code.writeln();
        code.writeln(name);
    }
    else
    {
        if (name.length)
        {
            if (code.inLine && code.data.length
                    && !code.data[$ - 1].inCharSet!" \t"
                    && code.data[$ - 1].inCharSet!"a-zA-Z0-9_" && name[0].inCharSet!"a-zA-Z0-9_")
                code.write(" ");
            code.write(name);
        }
    }
}

enum TreeToCodeFlags
{
    none = 0,
    skipCasts = 1,
    inStatementExpression = 2,
}

void parseTreeToDCode(T)(ref CodeWriter code, DWriterData data, T tree, immutable(Formula)* condition,
        Scope currentScope, TreeToCodeFlags treeToCodeFlags = TreeToCodeFlags.none)
{
    auto semantic = data.semantic;
    auto logicSystem = data.logicSystem;
    alias Location = typeof(() { return tree.start; }());
    if (!tree.isValid)
        return;

    Scope origScope = currentScope;
    if (currentScope !is null && tree in currentScope.childScopeByTree)
        currentScope = currentScope.childScopeByTree[tree];

    size_t indexInParent;
    size_t indexInParent2;
    Tree parent = getRealParent(tree, semantic, &indexInParent);
    Tree parent2 = getRealParent(parent, semantic, &indexInParent2);
    Tree parent3 = getRealParent(parent2, semantic);

    if (parent.isValid && parent.nameOrContent == "CtorInitializer"
            && tree.nodeType == NodeType.token && tree.nameOrContent.strip == ",")
        return;

    auto wholeExpressionWrapper = ConditionalCodeWrapper(condition, data);

    string macroReplacement;
    immutable(LocationContext)* macroReplacementLoc = hasMacroReplacement(data,
            tree.start.context, macroReplacement);

    if (semantic.logicSystem.and(typeKindIs(semantic.extraInfo2(tree)
            .convertedType.type, TypeKind.pointer, semantic.logicSystem).negated, condition).isFalse
            && tree.nameOrContent == "Literal" && tree.childs[0].content == "0")
    {
        macroReplacement = "null";
        macroReplacementLoc = tree.start.context;
    }

    if (data.sourceTokenManager.tokensLeft.data.length > 0
            && !(tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                || tree.nodeType == NodeType.merged) && tree.nodeType != NodeType.array
            && !(tree.nodeType == NodeType.nonterminal
                && tree.nonterminalID.nonterminalIDAmong!("BaseClause",
                "FunctionBody", "MemInitializer")))
    {
        writeComments(code, data, locationBeforeUsedMacro(tree, data,
                macroReplacementLoc !is null));
    }

    bool skipCasts = (treeToCodeFlags & TreeToCodeFlags.skipCasts) != 0;

    if (tree in data.macroReplacement)
    {
        auto instance = data.macroReplacement[tree];
        if (tree !is instance.firstUsedTree)
            return;
        if (instance.macroDeclaration.type == DeclarationType.macroParam)
            skipCasts = true;
    }

    if (!skipCasts && semantic.extraInfo2(tree).convertedType.type !is null
            && semantic.extraInfo(tree).type.type !is null)
    {
        immutable(Formula)* needsCastCondition = semantic.logicSystem.false_;
        immutable(Formula)* needsCastStaticArrayCondition = semantic.logicSystem.false_;
        calcNeedsCast(needsCastCondition, needsCastStaticArrayCondition, data,
                tree, condition, currentScope, &wholeExpressionWrapper);

        if ((macroReplacement == "null" || (tree.nonterminalID == nonterminalIDFor!"PointerLiteral"
                && tree.childs[0].content.endsWith("nullptr")))
                && semantic.logicSystem.and(typeKindIs(semantic.extraInfo2(tree)
                    .convertedType.type, TypeKind.pointer, semantic.logicSystem).negated, condition)
                    .isFalse)
            needsCastCondition = semantic.logicSystem.false_;

        needsCastCondition = simplifyMergedCondition(needsCastCondition, semantic.logicSystem);
        if (!needsCastCondition.isFalse)
        {
            ConditionMap!string codeType;
            wholeExpressionWrapper.add("cast(" ~ typeToCode(semantic.extraInfo2(tree).convertedType,
                    data, condition, currentScope, tree.location, [], codeType) ~ ") (",
                    ")", condition /*needsCastCondition*/ );
        }
        if (!needsCastStaticArrayCondition.isFalse)
        {
            ConditionMap!string codeType;
            wholeExpressionWrapper.add("castStaticArray!( " ~ typeToCode(semantic.extraInfo2(tree)
                    .convertedType, data,
                    needsCastStaticArrayCondition, currentScope, tree.location, [], codeType) ~ " ) (",
                    ")", needsCastStaticArrayCondition);
        }
    }

    wholeExpressionWrapper.begin(code, condition);
    scope (success)
        wholeExpressionWrapper.end(code, condition);

    scope (success)
    {
        if (data.sourceTokenManager.tokensLeft.data.length && tree.location.context !is null)
        {
            auto endTokens = data.sourceTokenManager.collectTokens(tree.location.end);
            //assert(endTokens.length == 0, text(tree.name, " ", locationStr(tree.start), " ", locationStr(tree.end, true)));
            writeComments(code, data, endTokens);
        }
    }

    if (tree in data.macroReplacement)
    {
        auto instance = data.macroReplacement[tree];
        if (tree !is instance.firstUsedTree)
            return;
        bool needsParens = false;

        if (instance.macroTranslation == MacroTranslation.mixin_ && parent.isValid)
        {
            if (parent.nonterminalID.nonterminalIDAmong!( /*"ArrayDeclarator", */ "ExpressionStatement"))
                needsParens = true;
            if (parent.nameOrContent == "PostfixExpression"
                    && parent.childs[1].nameOrContent == "[" && indexInParent == 2)
                needsParens = true; // see test145.cpp
            if (treeToCodeFlags & TreeToCodeFlags.inStatementExpression)
                needsParens = true;
        }

        string name = instance.usedName;

        name = qualifyName(name, instance.macroDeclaration, data, currentScope, condition);

        bool possibleStringLiteral = instance.macroTranslation == MacroTranslation.enumValue || instance.hasParamExpansion;
        if (data.afterStringLiteral && possibleStringLiteral)
            code.write("~ ");
        if (instance.macroDeclaration.type == DeclarationType.macroParam)
        {
            if (instance.macroTranslation == MacroTranslation.enumValue)
            {
                code.write(instance.usedName);
            }
            else if (instance.macroTranslation == MacroTranslation.alias_)
            {
                code.write(instance.usedName);
            }
            else if (instance.hasParamExpansion)
            {
                code.write("$(stringifyMacroParameter(", instance.usedName, "))");
            }
            else
                code.write("$(", instance.usedName, ")");
            if (data.sourceTokenManager.tokensLeft.data.length)
                data.sourceTokenManager.collectTokens(tree.location.end);
            data.afterStringLiteral = possibleStringLiteral; // Any macro could be a string.
        }
        else if (instance.macroTranslation.among(MacroTranslation.enumValue,
                MacroTranslation.mixin_, MacroTranslation.alias_, MacroTranslation.builtin))
        {
            if (code.inLine && code.data.length
                    && !code.data[$ - 1].inCharSet!" \t" && !code.data.endsWith("("))
                code.write(" ");

            string macroSuffix;
            if (needsParens)
            {
                code.write("(");
                macroSuffix = ")" ~ macroSuffix;
            }
            if (instance.macroTranslation.among(MacroTranslation.enumValue,
                    MacroTranslation.builtin))
            {
            }
            else if (instance.macroTranslation == MacroTranslation.mixin_)
            {
                if (tree.nonterminalID == nonterminalIDFor!"TypeId")
                {
                    code.write("Identity!(");
                    macroSuffix = ")" ~ macroSuffix;
                }
                code.write("mixin(");
                macroSuffix = ")" ~ macroSuffix;
            }
            parseTreeToCodeTerminal(code, name);

            assert(instance.locationContextInfo.locationContext.name == "^");
            assert(instance.locationContextInfo.locationContext.prev.name
                    == instance.locationContextInfo.locationContext.prev.prev.name);
            bool allowComments = instance.locationContextInfo.locationContext.prev.prev.prev.name == ""
                || instance.locationContextInfo.locationContext.prev.prev.prev is data.sourceTokenManager.tokensContext;

            if (data.sourceTokenManager.tokensLeft.data.length
                    && instance.macroDeclaration.type == DeclarationType.macro_
                    && instance.macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine"
                    && allowComments)
            {
                outer: do
                {
                    auto tokens = data.sourceTokenManager.collectTokens(tree.location.end);
                    if (tokens.length == 0 || tokens[0].isWhitespace)
                        break outer;
                    assert(!tokens[0].isWhitespace, text(locationStr(tree.start),
                            " ", locationStr(tree.end, true))); // Name
                    tokens = tokens[1 .. $];
                    size_t paren = size_t.max;
                    foreach (i, t; tokens)
                    {
                        if (!t.isWhitespace)
                        {
                            if (t.token.content != "(")
                            {
                                code.write("/* TODO: strange func macro */");
                                break outer;
                            }
                            assert(t.token.content == "(");
                            paren = i;
                            break;
                        }
                    }
                    if (paren == size_t.max)
                        break outer;
                    assert(paren != size_t.max);
                    writeComments(code, data, tokens[0 .. paren]);
                }
                while (false);
            }

            if (instance.macroDeclaration.type == DeclarationType.macro_
                    && instance.macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
            {
                parseTreeToCodeTerminal(code, (instance.macroTranslation.among(MacroTranslation.mixin_,
                        MacroTranslation.builtin)) ? "(" : "!(");
                bool first = true;

                foreach (paramName; instance.paramNames)
                {
                    if (!first)
                        parseTreeToCodeTerminal(code, ",");
                    first = false;

                    if (data.options.addDeclComments)
                        code.write("/*", paramName.usedName, "*/");
                    string codePrefix, codeSuffix;
                    if (instance.macroTranslation == MacroTranslation.mixin_)
                    {
                        codePrefix = "q{";
                        codeSuffix = "}";
                    }
                    if (paramName.realName in instance.params)
                    {
                        auto paramInstances = instance.params[paramName.realName].instances;
                        MacroDeclarationInstance x;
                        bool allCodesSame = true;
                        foreach (y; paramInstances)
                        {
                            if (y.usedName == paramName.usedName)
                            {
                                x = y;
                            }
                            if (y.instanceCode != paramInstances[0].instanceCode)
                                allCodesSame = false;
                        }
                        if (!allCodesSame)
                            code.write("/* WARNING: Parameter has been split. */");
                        code.write(x.instanceCode[0 .. x.realCodeStart]);
                        code.write(codePrefix);
                        code.write(x.instanceCode[x.realCodeStart .. x.realCodeEnd]);
                        code.write(codeSuffix);
                        code.write(x.instanceCode[x.realCodeEnd .. $]);
                    }
                    else
                    {
                        code.write(codePrefix);
                        LocationRangeX locRange = instance.locationContextInfo.locationContext
                            .parentLocation.context.parentLocation.context.parentLocation;

                        SourceToken[] tokens = (locRange.context.name.length
                                ? data.sourceTokenManager.sourceTokensMacros : data.sourceTokenManager.sourceTokens)[RealFilename(
                                    locRange.context.filename)];

                        while (tokens.length && tokens[0].token.start.loc < locRange.start.loc)
                            tokens = tokens[1 .. $];
                        while (tokens.length && tokens[$ - 1].token.end.loc > locRange.end.loc)
                            tokens = tokens[0 .. $ - 1];

                        while (tokens.length && tokens[0].isWhitespace)
                            tokens = tokens[1 .. $];
                        if (tokens.length)
                            tokens = tokens[1 .. $];
                        while (tokens.length && tokens[0].isWhitespace)
                            tokens = tokens[1 .. $];
                        while (tokens.length && tokens[$ - 1].isWhitespace)
                            tokens = tokens[0 .. $ - 1];
                        if (tokens.length)
                        {
                            assert(tokens[0].token.content == "(");
                            tokens = tokens[1 .. $];
                            assert(tokens[$ - 1].token.content == ")");
                            tokens = tokens[0 .. $ - 1];

                            SourceToken[][] splitTokens = [[]];
                            size_t numParens;
                            foreach (t; tokens)
                            {
                                if (t.token.nameOrContent == "(")
                                    numParens++;
                                else if (t.token.nameOrContent == ")")
                                {
                                    assert(numParens);
                                    numParens--;
                                }
                                if (numParens == 0 && t.token.nameOrContent == ",")
                                    splitTokens ~= SourceToken[].init;
                                else
                                    splitTokens[$ - 1] ~= t;
                            }

                            foreach (i, t; splitTokens[paramName.index])
                            {
                                if (t.token.nodeType != NodeType.token)
                                    continue;

                                string content = t.token.content;
                                if (t.token.nodeType == NodeType.token && t.isWhitespace)
                                {
                                    if (content.among("\\\n", "\\\r\n"))
                                    {
                                        code.writeln();
                                        continue;
                                    }
                                }

                                code.write(content);
                            }
                        }
                        code.write(codeSuffix);
                    }
                }
                parseTreeToCodeTerminal(code, ")");
            }
            parseTreeToCodeTerminal(code, macroSuffix);
            if (data.sourceTokenManager.tokensLeft.data.length && allowComments)
                data.sourceTokenManager.collectTokens(tree.location.end);
            if (instance.macroTranslation == MacroTranslation.mixin_
                    && (tree.name.endsWith("Statement") || (tree.nodeType == NodeType.merged && tree.nonterminalID == nonterminalIDFor!"Statement") || tree.nonterminalID == nonterminalIDFor!"StaticAssertDeclaration" || parent.nonterminalID == nonterminalIDFor!"ClassBody"))
                parseTreeToCodeTerminal(code, ";");
            else
                data.afterStringLiteral = possibleStringLiteral; // Any macro could be a string.
        }

        return;
    }

    if (macroReplacementLoc !is null)
    {
        assert(macroReplacement.length);
        if (data.sourceTokenManager.tokensLeft.data.length)
        {
            writeComments(code, data, locationBeforeUsedMacro(tree, data, true));
            data.sourceTokenManager.collectTokens(tree.end);
        }
        parseTreeToCodeTerminal(code, macroReplacement);
        return;
    }

    scope(success)
    {
        if (tree.nodeType == NodeType.token
                || (tree.nodeType == NodeType.nonterminal
                    && tree.nonterminalID != nonterminalIDFor!"StringLiteral2"
                    && tree.nonterminalID != CONDITION_TREE_NONTERMINAL_ID))
            data.afterStringLiteral = false;
    }

    if (tree.nodeType == NodeType.token)
    {
        string name = tree.content.strip;
        if (name == "::")
            name = ".";
        parseTreeToCodeTerminal(code, name);

        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            data.sourceTokenManager.collectTokens(tree.end);
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        if (!semantic.logicSystem.and(mdata.mergedCondition, condition).isFalse)
        {
            size_t numNonFalse;
            size_t index;
            foreach (i, c; mdata.conditions)
            {
                if (!semantic.logicSystem.and(c, condition).isFalse)
                {
                    numNonFalse++;
                    index = i;
                }
            }
            if (numNonFalse == 1)
            {
                code.writeln();
                code.writeln("// WARNING: ambiguous for condition ",
                        semantic.logicSystem.and(mdata.mergedCondition, condition).toString);
                parseTreeToDCode(code, data, tree.childs[index], condition, currentScope);
                return;
            }
        }

        conditionTreeToDCode(code, data, tree, tree.childs ~ tree,
                mdata.conditions ~ mdata.mergedCondition, logicSystem,
                condition, currentScope, treeToCodeFlags);
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        conditionTreeToDCode(code, data, tree, ctree.childs, ctree.conditions,
                logicSystem, condition, currentScope, treeToCodeFlags);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"EmptyStatement")
    {
        if (parent.nonterminalID == nonterminalIDFor!"Statement"
                && parent2.nonterminalID == nonterminalIDFor!"CompoundStatement")
        {
            skipToken(code, data, tree.childs[0]);
        }
        else if (parent.nonterminalID == nonterminalIDFor!"Statement"
                && parent2.nonterminalID.nonterminalIDAmong!("IterationStatement",
                    "IfStatement", "ElseIfStatement", "ElseStatement", "SwitchStatement",
                    "DoWhileStatement"))
        {
            parseTreeToCodeTerminal(code, "{");
            parseTreeToCodeTerminal(code, "}");
            skipToken(code, data, tree.childs[0]);
        }
        else
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"FunctionBody")
    {
        enforce(tree.childs[1].nonterminalID == nonterminalIDFor!"CompoundStatement");
        Tree compoundStmt = tree.childs[1];

        bool putCloseNewline;

        string origCustomIndent = code.customIndent;
        scope (success)
            code.customIndent = origCustomIndent;

        CodeWriter code2;
        code2.indentStr = data.options.indent;
        if (tree.childs[0].isValid)
        {
            string lastLineIndent;
            getLastLineIndent(code, lastLineIndent);
            SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.childs[0].start, false);
            while (tokens.length && tokens[0].isWhitespace
                    && (tokens[0].token.content.startsWith(" ")
                        || tokens[0].token.content.startsWith("\t")
                        || tokens[0].token.content == "\n" || tokens[0].token.content == "\r\n"))
                tokens = tokens[1 .. $];
            while (tokens.length && tokens[$ - 1].isWhitespace
                    && (tokens[$ - 1].token.content.startsWith(" ")
                        || tokens[$ - 1].token.content.startsWith("\t")
                        || tokens[$ - 1].token.content == "\n"
                        || tokens[$ - 1].token.content == "\r\n"))
                tokens = tokens[0 .. $ - 1];
            writeComments(code, data, tokens);

            string lastLineIndentUnused;
            if (getLastLineIndent(code, lastLineIndentUnused))
            {
                code.customIndent = "";
                code.writeln();
                code.write(lastLineIndent);
                code.customIndent = origCustomIndent;
            }
            putCloseNewline = true;

            parseTreeToDCode(code2, data, tree.childs[0], condition, currentScope);

            tokens = data.sourceTokenManager.collectTokens(compoundStmt.childs[0].start, false);
            while (tokens.length && tokens[0].isWhitespace
                    && (tokens[0].token.content.startsWith(" ")
                        || tokens[0].token.content.startsWith("\t")
                        || tokens[0].token.content == "\n" || tokens[0].token.content == "\r\n"))
                tokens = tokens[1 .. $];
            while (tokens.length && tokens[$ - 1].isWhitespace
                    && (tokens[$ - 1].token.content.startsWith(" ")
                        || tokens[$ - 1].token.content.startsWith("\t")
                        || tokens[$ - 1].token.content == "\n"
                        || tokens[$ - 1].token.content == "\r\n"))
                tokens = tokens[0 .. $ - 1];
            writeComments(code, data, tokens);
        }

        parseTreeToDCode(code, data, compoundStmt.childs[0], condition, currentScope); // {
        string lastLineIndent;
        getLastLineIndent(code, lastLineIndent);
        bool haveIncludes;
        auto importGraphLocal = getNeededImportsLocal(data.currentDeclaration, data);
        if (importGraphLocal !is null)
        {
            if (writeImports(code, data, importGraphLocal, condition, true))
                putCloseNewline = true;
        }

        if (code2.data)
        {
            code.customIndent = lastLineIndent ~ data.options.indent;
            string lastLineIndentUnused;
            if (getLastLineIndent(code, lastLineIndentUnused))
            {
                code.writeln();
            }
            code.write(code2.data);
            code.customIndent = origCustomIndent;
        }

        if (currentScope !is null && compoundStmt in currentScope.childScopeByTree)
            currentScope = currentScope.childScopeByTree[compoundStmt];

        if (putCloseNewline && compoundStmt.childs[1].isValid
                && compoundStmt.childs[1].childs.length)
        {
            SourceToken[] tokens = data.sourceTokenManager.collectTokens(
                    compoundStmt.childs[1].start, false);
            while (tokens.length && tokens[0].isWhitespace
                    && (tokens[0].token.content.startsWith(" ")
                        || tokens[0].token.content.startsWith("\t")))
                tokens = tokens[1 .. $];
            bool hasNewline;
            foreach (t; tokens)
                if (tokens[0].isWhitespace && (tokens[0].token.content == "\n"
                        || tokens[0].token.content == "\r\n"))
                    hasNewline = true;
            if (!hasNewline)
            {
                while (tokens.length && tokens[$ - 1].isWhitespace
                        && (tokens[$ - 1].token.content.startsWith(" ")
                            || tokens[$ - 1].token.content.startsWith("\t")))
                    tokens = tokens[0 .. $ - 1];
            }
            writeComments(code, data, tokens);
            if (!hasNewline)
            {
                string lastLineIndentUnused;
                if (!code.inLine || getLastLineIndent(code, lastLineIndentUnused))
                {
                    code.customIndent = "";
                    if (code.inLine)
                        code.writeln();
                    code.write(lastLineIndent);
                    code.write(data.options.indent);
                    code.customIndent = origCustomIndent;
                }
            }
        }

        parseTreeToDCode(code, data, compoundStmt.childs[1], condition, currentScope);
        immutable(Formula)* conditionIsStatementEndUnreachable = semantic.logicSystem.false_;
        isStatementEndUnreachable(compoundStmt.childs[1], condition, semantic,
                data, conditionIsStatementEndUnreachable);

        QualType resultType = functionResultType(data.currentDeclaration.type2, semantic);
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            auto t = chooseType(resultType, ppVersion, true);
            if (t.kind == TypeKind.builtin && t.name == "void")
                conditionIsStatementEndUnreachable = semantic.logicSystem.and(
                        conditionIsStatementEndUnreachable, ppVersion.condition.negated);
        }

        if (semantic.logicSystem.and(conditionIsStatementEndUnreachable.negated, condition).isFalse)
        {
            parseTreeToCodeTerminal(code, "assert(false)");
            parseTreeToCodeTerminal(code, ";");
            code.writeln();
        }
        else if (!semantic.logicSystem.and(conditionIsStatementEndUnreachable, condition).isFalse)
        {
            code.writeln("static if (", conditionToDCode(semantic.logicSystem.and(condition,
                    conditionIsStatementEndUnreachable), data), ")");
            code.writeln("{");
            code.writeln(code.indentStr, "assert(false);");
            code.writeln("}");
        }
        if (putCloseNewline)
        {
            if (data.sourceTokenManager.tokensLeft.data.length && tree.location.context !is null)
            {
                auto tokens = data.sourceTokenManager.collectTokens(
                        compoundStmt.childs[2].location.start); // tokens before }

                while (tokens.length && tokens[$ - 1].isWhitespace
                        && (tokens[$ - 1].token.content.startsWith(" ")
                            || tokens[$ - 1].token.content.startsWith("\t")))
                {
                    tokens = tokens[0 .. $ - 1];
                }

                bool alwaysNewline;
                if (tokens.length && tokens[$ - 1].isWhitespace
                        && (tokens[$ - 1].token.content == "\n"
                            || tokens[$ - 1].token.content == "\r\n"))
                {
                    tokens = tokens[0 .. $ - 1];
                    writeComments(code, data, tokens);
                    alwaysNewline = true;
                }
                else
                {
                    writeComments(code, data, tokens);
                }

                string lastLineIndentUnused;
                if (alwaysNewline || !code.inLine || getLastLineIndent(code, lastLineIndentUnused))
                {
                    code.customIndent = "";
                    if (code.inLine)
                        code.writeln();
                    code.write(lastLineIndent);
                    code.customIndent = origCustomIndent;
                }
            }
        }
        parseTreeToDCode(code, data, compoundStmt.childs[2], condition, currentScope); // }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CtorInitializer")
    {
        SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.start, false);
        while (tokens.length && tokens[0].isWhitespace
                && (tokens[0].token.name.startsWith(" ")
                    || tokens[0].token.name.startsWith("\t")
                    || tokens[0].token.name == "\n" || tokens[0].token.name == "\r\n"))
            tokens = tokens[1 .. $];
        while (tokens.length && tokens[$ - 1].isWhitespace
                && (tokens[$ - 1].token.name.startsWith(" ")
                    || tokens[$ - 1].token.name.startsWith("\t")
                    || tokens[$ - 1].token.name == "\n" || tokens[$ - 1].token.name == "\r\n"))
            tokens = tokens[0 .. $ - 1];
        writeComments(code, data, tokens);

        skipToken(code, data, tree.childs[0]);

        tokens = data.sourceTokenManager.collectTokens(tree.start, false);
        while (tokens.length && tokens[0].isWhitespace
                && (tokens[0].token.name.startsWith(" ")
                    || tokens[0].token.name.startsWith("\t")
                    || tokens[0].token.name == "\n" || tokens[0].token.name == "\r\n"))
            tokens = tokens[1 .. $];
        while (tokens.length && tokens[$ - 1].isWhitespace
                && (tokens[$ - 1].token.name.startsWith(" ")
                    || tokens[$ - 1].token.name.startsWith("\t")
                    || tokens[$ - 1].token.name == "\n" || tokens[$ - 1].token.name == "\r\n"))
            tokens = tokens[0 .. $ - 1];
        writeComments(code, data, tokens);

        foreach (c; tree.childs[1 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"MemInitializer")
    {
        CodeWriter code2;
        code2.indentStr = data.options.indent;

        SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.start, false);
        for (size_t i = 0; i < tokens.length;)
            if (tokens[i].token.nodeType == NodeType.token && tokens[i].token.content == ",")
                tokens = tokens[0 .. i] ~ tokens[i + 1 .. $];
            else
                i++;
        while (tokens.length && tokens[0].isWhitespace
                && (tokens[0].token.content.startsWith(" ")
                    || tokens[0].token.content.startsWith("\t")
                    || tokens[0].token.content == "\n" || tokens[0].token.content == "\r\n"))
            tokens = tokens[1 .. $];
        while (tokens.length && tokens[$ - 1].isWhitespace
                && (tokens[$ - 1].token.content.startsWith(" ")
                    || tokens[$ - 1].token.content.startsWith("\t")
                    || tokens[$ - 1].token.content == "\n" || tokens[$ - 1].token.content == "\r\n"))
            tokens = tokens[0 .. $ - 1];
        writeComments(code, data, tokens);

        parseTreeToDCode(code2, data, tree.childs[0], condition, currentScope);

        auto codeWrapper = ConditionalCodeWrapper(condition, data);
        outer2: foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            Tree t1 = ppVersion.chooseTree(tree.childs[0]);

            if (t1.nonterminalID == nonterminalIDFor!"ClassOrDecltype" && !t1.childs[0].isValid)
            {
                Tree t2 = ppVersion.chooseTree(t1.childs[1]);
                if (t2.nonterminalID == nonterminalIDFor!"NameIdentifier")
                {
                    ConditionMap!Declaration realDecl;
                    findRealDecl(t2, realDecl, ppVersion.condition, data, true, currentScope);
                    foreach (e; realDecl.entries)
                    {
                        if (isInCorrectVersion(ppVersion,
                                logicSystem.and(e.condition, e.data.condition)))
                        {
                            if (e.data.type == DeclarationType.type)
                            {
                                if (e.data is data.currentClassDeclaration)
                                    codeWrapper.add("this(", ")", ppVersion.condition);
                                else if (isStruct(data.currentClassDeclaration.tree, data))
                                    codeWrapper.add("this.base0 = " ~ code2.data.idup ~ "(",
                                            ")", ppVersion.condition);
                                else
                                    codeWrapper.add("super(", ")", ppVersion.condition);
                                continue outer2;
                            }
                        }
                    }
                }
            }

            auto t = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);

            if (t.kind.among(TypeKind.builtin, TypeKind.pointer,
                    TypeKind.array) || tree.childs.length == 4
                    && tree.childs[2].isValid && tree.childs[2].childs.length == 1)
                codeWrapper.add(text("this.", code2.data, " = "), "", ppVersion.condition);
            else
                codeWrapper.add(text("this.", code2.data, " = typeof(this.",
                        code2.data, ")("), ")", ppVersion.condition);
        }

        codeWrapper.begin(code, condition);
        if (tree.childs.length == 4)
        {
            skipToken(code, data, tree.childs[1]);
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
            skipToken(code, data, tree.childs[3]);
        }
        else
            foreach (c; tree.childs[1 .. $])
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        codeWrapper.end(code, condition);
        code.writeln(";");
    }
    else if (tree.nonterminalID == nonterminalIDFor!"DoWhileStatement")
    {
        foreach (c; tree.childs)
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }

        parseTreeToCodeTerminal(code, ";");
        //code.writeln();
    }
    else if (auto match = tree.matchTreePattern!q{
            IterationStatement(*, ";")
        })
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        skipToken(code, data, tree.childs[1]);
    }
    else if ((tree.nonterminalID == nonterminalIDFor!"SwitchStatement"
            && !(tree.childs[$ - 1].nameOrContent == "Statement"
            && tree.childs[$ - 1].childs[1].nameOrContent == "CompoundStatement"))
            || isCompoundStatementInSwitch(tree, semantic))
    {
        immutable(Formula)* hasDefault = semantic.logicSystem.false_;
        void findDefault(Tree tree, immutable(Formula)* condition)
        {
            if (tree.nodeType == NodeType.array)
            {
                foreach (c; tree.childs)
                    findDefault(c, condition);
            }
            else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                auto ctree = tree.toConditionTree;
                assert(ctree !is null);
                foreach (i; 0 .. ctree.conditions.length)
                {
                    findDefault(ctree.childs[i],
                            semantic.logicSystem.and(condition, ctree.conditions[i]));
                }
            }
            else if (tree.nameOrContent == "LabelStatement"
                    && tree.childs[1].nameOrContent == "default")
            {
                hasDefault = semantic.logicSystem.or(hasDefault, condition);
            }
        }

        string lastLineIndent;
        if (tree.nonterminalID == nonterminalIDFor!"CompoundStatement")
        {
            foreach (c; tree.childs)
                findDefault(c, condition);
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        }
        else
        {
            foreach (c; tree.childs[0 .. $ - 1])
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
            findDefault(tree.childs[$ - 1], condition);

            if (getLastLineIndent(code, lastLineIndent))
                code.writeln();
            code.writeln(lastLineIndent, "{");
            parseTreeToDCode(code, data, tree.childs[$ - 1], condition, currentScope);
        }

        auto labelNeedsGoto = semantic.extraInfo2(parent2).labelNeedsGoto;
        if (labelNeedsGoto is null)
            labelNeedsGoto = semantic.logicSystem.false_;
        labelNeedsGoto = semantic.logicSystem.and(condition, labelNeedsGoto);

        if (hasDefault.isFalse)
        {
            if (!labelNeedsGoto.isFalse)
                code.writeln("goto default;");
            code.writeln("default:");
        }
        else if (!semantic.logicSystem.and(condition, hasDefault.negated).isFalse)
        {
            code.writeln("static if (", conditionToDCode(semantic.logicSystem.and(condition,
                    hasDefault.negated), data), ")");
            code.writeln("{");
            if (!labelNeedsGoto.isFalse)
                code.writeln("goto default;");
            code.writeln(code.indentStr, "default:");
            code.writeln("}");
        }

        if (tree.nonterminalID == nonterminalIDFor!"CompoundStatement")
        {
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        }
        else
        {
            string lastLineIndent2;
            if (getLastLineIndent(code, lastLineIndent2))
                code.writeln();
            code.writeln(lastLineIndent, "}");
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"LabelStatement")
    {
        auto labelNeedsGoto = semantic.extraInfo2(tree).labelNeedsGoto;
        if (labelNeedsGoto is null)
            labelNeedsGoto = semantic.logicSystem.false_;
        labelNeedsGoto = semantic.logicSystem.and(condition, labelNeedsGoto);

        if (!labelNeedsGoto.isFalse)
        {
            if (tree.childs[1].content == "case")
                code.writeln("goto case;");
            else if (tree.childs[1].content == "default")
                code.writeln("goto default;");
        }

        if (!tree.childs[1].content.among("case", "default"))
        {
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            parseTreeToCodeTerminal(code, replaceKeywords(tree.childs[1].content));
            skipToken(code, data, tree.childs[1]);
            foreach (c; tree.childs[2 .. $])
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            IfStatementHead("if", "constexpr", ...)
        })
    {
        code.write("static ");
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        skipToken(code, data, tree.childs[1], false, true);
        foreach (c; tree.childs[2 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("IfStatement"))
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);

        codeWrapper.checkTree(tree.childs, false);

        if (codeWrapper.alwaysUseMixin)
        {
            codeWrapper.begin(code, condition);

            void onTree(Tree t, immutable(Formula)* condition2)
            {
                parseTreeToDCode(code, data, t, condition2, currentScope);
                writeComments(code, data, data.sourceTokenManager.collectTokens(t.location.end));
                writeComments(code, data,
                        data.sourceTokenManager.collectTokensUntilLineEnd(t.location.end,
                            condition));
            }

            code.incIndent;
            codeWrapper.writeTree(code, &onTree, tree.childs);
            code.decIndent;

            codeWrapper.end(code, condition);
            code.write(";");
        }
        else
        {
            foreach (c; tree.childs)
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("ClassHead", "EnumHead"))
    {
        string name = chooseDeclarationName(data.currentDeclaration, data);

        string templateParamCode = data.declarationData(data.currentDeclaration).templateParamCode;

        foreach (i, c; tree.childs)
        {
            if (i == 1)
                continue;
            if (tree.childName(i) == "name")
            {
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                {
                    writeComments(code, data, tree.childs[i].start);
                }
            }
            if (tree.childName(i) == "name" || (!tree.hasChildWithName("name") && i == 2))
            {
                if (name.length)
                {
                    if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                        code.write(" ");
                    code.write(name);
                }
                if (templateParamCode.length)
                {
                    code.write("(", templateParamCode, ")");
                    data.declarationData(data.currentDeclaration).templateParamCode = "";
                }
            }
            if (tree.childName(i) == "name")
            {
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                {
                    writeComments(code, data, tree.childs[i].start);
                    writeComments(code, data, tree.childs[i].end, true);
                }
            }
            if (tree.childName(i) != "name")
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"Enumerator")
    {
        assert(semantic.extraInfo(tree).declarations.length == 1, text(locationStr(tree.location)));
        string name = chooseDeclarationName(semantic.extraInfo(tree).declarations[0], data);

        skipToken(code, data, tree.childs[0]);
        code.write(name);

        foreach (c; tree.childs[2 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
    {
        parseTreeToDCode(code, data, tree.childs[$ - 1], condition, currentScope);
    }
    else if (tree.name.startsWith("SimpleDeclaration") || tree.name.startsWith("MemberDeclaration")
            || tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal", "MemberDeclaration" /*, "ParameterDeclaration", "ParameterDeclarationAbstract"*/ ,
                "Condition", "AliasDeclaration", "UsingDeclaration",
                "ForRangeDeclaration", "ExceptionDeclaration", "LambdaExpression"))
    {
        bool hasDecls;
        foreach (d; semantic.extraInfo(tree).declarations)
        {
            if (isDeclarationBlacklisted(data, d))
                continue;

            Scope parentScope = origScope;
            while (parentScope !is null && parentScope.tree.isValid
                    && parentScope.tree.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
                parentScope = parentScope.parentScope;

            if (parentScope !is null && d.scope_ !is parentScope)
                continue;
            declarationToDCode(code, data, d, condition);
            hasDecls = true;
        }
        if (hasDecls && tree.nonterminalID == nonterminalIDFor!"MemberDeclaration2")
            skipToken(code, data, tree.childs[$ - 1]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"TypeId")
    {
        Tree declSeq = tree.childs[0];

        ConditionMap!string codeType;
        CodeWriter codeAfterDeclSeq;
        codeAfterDeclSeq.indentStr = data.options.indent;
        bool afterTypeInDeclSeq;
        if (declSeq.isValid && data.sourceTokenManager.tokensLeft.data.length > 0)
        {
            collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                    afterTypeInDeclSeq, declSeq, condition, data, currentScope);
            if (tree.childs[1].isValid)
                writeComments(codeAfterDeclSeq, data, tree.childs[1].start);
        }

        Tree realDeclarator = tree.childs[1];
        auto type = semantic.extraInfo(tree).type;

        DeclaratorData[] declList = declaratorList(realDeclarator, condition, data, currentScope);

        string typeCode2 = typeToCode(type, data, condition, currentScope,
                tree.location, declList, codeType);
        typeCode2 ~= codeAfterDeclSeq.data;
        while (typeCode2.length && typeCode2[$ - 1].inCharSet!" \t")
            typeCode2 = typeCode2[0 .. $ - 1];
        code.write(typeCode2);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CastExpression")
    {
        parseTreeToCodeTerminal(code, "cast");
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);

        string suffix;
        if (tree.childs[$ - 1].nonterminalID == nonterminalIDFor!"LiteralS"
                && tree.childs[$ - 1].childs[0].nonterminalID == nonterminalIDFor!"StringLiteralSequence"
                && (tree.childs[$ - 1].childs[0].childs[0].childs.length != 1 || tree.childs[$ - 1].childs[0].childs[0].childs[0].nonterminalID != nonterminalIDFor!"StringLiteral2"))
        {
            code.write("(");
            suffix = ")";
        }
        foreach (c; tree.childs[1 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
        code.write(suffix);
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("sizeof" | "alignof" | "__alignof__", "(", *, ")")
        })
    {
        // "sizeof" "(" TypeId ")"
        assert(tree.childs[1].content == "(");
        assert(tree.childs[3].content == ")");

        auto type = semantic.extraInfo(tree.childs[2]).type;
        skipToken(code, data, tree.childs[0]);
        skipToken(code, data, tree.childs[1]);
        if (type.type !is null && type.kind.among(TypeKind.array,
                TypeKind.pointer, TypeKind.condition))
            code.write("(");
        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        skipToken(code, data, tree.childs[3]);
        if (type.type !is null && type.kind.among(TypeKind.array,
                TypeKind.pointer, TypeKind.condition))
            code.write(")");
        if (tree.childs[0].content == "sizeof")
            parseTreeToCodeTerminal(code, ".sizeof");
        else
            parseTreeToCodeTerminal(code, ".alignof");
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("sizeof", *)
        })
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);

        skipToken(code, data, tree.childs[0]);

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            auto t = chooseType(semantic.extraInfo(tree.childs[1]).type, ppVersion, true);

            if (t.type !is null && t.kind == TypeKind.array)
            {
                auto atype = cast(ArrayType) t.type;
                auto t2 = chooseType(atype.next, ppVersion, true);
                if (t2.type !is null && t2.kind == TypeKind.builtin
                        && t2.name.among("char", "wchar", "char16", "char32"))
                {
                    Tree innerTree = ppVersion.chooseTree(tree.childs[1]);
                    while (innerTree.nameOrContent == "PrimaryExpression"
                            && innerTree.childs.length == 3
                            && innerTree.childs[0].nameOrContent == "(")
                        innerTree = ppVersion.chooseTree(innerTree.childs[1]);

                    ConditionMap!string codeType;
                    if (innerTree.nonterminalID == nonterminalIDFor!"LiteralS")
                        codeWrapper.add("( ", ".length + 1 ) * " ~ typeToCode(QualType(t2.type), data,
                                condition, currentScope, tree.location, [], codeType) ~ ".sizeof",
                                ppVersion.condition);
                    else
                        codeWrapper.add("( ", ".length ) * " ~ typeToCode(QualType(t2.type), data,
                                condition, currentScope, tree.location, [], codeType) ~ ".sizeof",
                                ppVersion.condition);
                    continue;
                }
            }
            if (tree.childs[1].nameOrContent.among("NameIdentifier")
                    || (tree.childs[1].nameOrContent == "PrimaryExpression"
                        && tree.childs[1].childs[0].nameOrContent == "("))
            {
                codeWrapper.add("", ". sizeof", ppVersion.condition);
            }
            else
            {
                codeWrapper.add("(", ") . sizeof", ppVersion.condition);
            }
        }

        codeWrapper.begin(code, condition);

        foreach (c; tree.childs[1 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }

        codeWrapper.end(code, condition);
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("__builtin_offsetof", "(", *, ",", *, ")")
        })
    {
        auto type = semantic.extraInfo(tree.childs[2]).type;
        skipToken(code, data, tree.childs[0]);
        skipToken(code, data, tree.childs[1]);
        if (type.type !is null && type.kind.among(TypeKind.array, TypeKind.pointer))
            code.write("(");
        if (data.sourceTokenManager.tokensLeft.data.length && tree.childs[2].isValid)
            writeComments(code, data, tree.childs[2].end, true);
        ConditionMap!string codeType;
        code.write(typeToCode(type, data, condition, currentScope,
                tree.location, [], codeType));
        if (type.type is null)
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        if (type.type !is null && type.kind.among(TypeKind.array, TypeKind.pointer))
            code.write(")");

        skipToken(code, data, tree.childs[3]);

        parseTreeToCodeTerminal(code, ".");
        skipToken(code, data, tree.childs[4]);
        parseTreeToCodeTerminal(code, tree.childs[4].content);
        parseTreeToCodeTerminal(code, ".offsetof");
        skipToken(code, data, tree.childs[5]);
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("__builtin_va_arg", "(", *, ",", *, ")")
        })
    {
        assert(tree.childs[1].content == "(");
        assert(tree.childs[5].content == ")");

        code.write(" va_arg!(");
        auto type = semantic.extraInfo(tree.childs[4]).type;
        ConditionMap!string codeType;
        code.write(typeToCode(type, data, condition, currentScope,
                tree.location, [], codeType));
        code.write(")(");
        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        code.write(")");
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].nameOrContent.startsWith("__builtin_va_"))
    {
        parseTreeToCodeTerminal(code, tree.childs[0].content["__builtin_".length .. $]);
        skipToken(code, data, tree.childs[0]);

        foreach (c; tree.childs[1 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("Literal", "FloatLiteral")
            || (tree.nonterminalID == nonterminalIDFor!"UserDefinedLiteral"
                && tree.childs[0].nameOrContent.endsWith("i64")))
    {
        string value = tree.childs[0].content;
        if (value.startsWith("0") && value.length >= 2 && value[1].inCharSet!"0-9")
        {
            string t = tree.childs[0].content;
            while (t.length >= 2 && t.startsWith("0"))
                t = t[1 .. $];
            parseTreeToCodeTerminal(code, "octal!" ~ t.replace("l", "L"));
        }
        else
        {
            value = value.replace("l", "L");
            if (value.endsWith("LL"))
                value = value[0 .. $ - 1];
            if (value.endsWith("i64"))
                value = value[0 .. $ - 3] ~ "L";
            parseTreeToCodeTerminal(code, value);
        }
        skipToken(code, data, tree.childs[0]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CharLiteral")
    {
        string value = tree.childs[0].content;
        if (value.startsWith("L'"))
            parseTreeToCodeTerminal(code, value[1 .. $]);
        else
        {
            parseTreeToCodeTerminal(code, value);
        }
        skipToken(code, data, tree.childs[0]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"LiteralS")
    {
        foreach (c; tree.childs)
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"StringLiteral2")
    {
        if (data.afterStringLiteral)
            code.write("~ ");
        string value = tree.childs[0].content;
        if (value.length >= 4 && value[$ - 4] == '\\' && value[$ - 3] == 'x' && value[$ - 1] == '"')
            value = value[0 .. $ - 2] ~ "0" ~ value[$ - 2 .. $];
        if (value.startsWith("L\""))
            parseTreeToCodeTerminal(code, "wchar_literal!" ~ value[1 .. $]);
        else if (value.startsWith("u8\""))
            parseTreeToCodeTerminal(code, value[2 .. $]);
        else if (value.startsWith("u\""))
            parseTreeToCodeTerminal(code, value[1 .. $] ~ "w");
        else if (value.startsWith("U\""))
            parseTreeToCodeTerminal(code, value[1 .. $] ~ "d");
        else
            parseTreeToCodeTerminal(code, value);
        skipToken(code, data, tree.childs[0]);
        data.afterStringLiteral = true;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CompoundLiteralExpression")
    {
        parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"BracedInitList"
        && parent.nonterminalID == nonterminalIDFor!"PostfixExpression" && parent.childs.length == 2 && indexInParent == 1)
    {
        skipToken(code, data, tree.childs[0]);
        code.write("(");
        parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        skipToken(code, data, tree.childs[2]);
        code.write(")");
    }
    else if (tree.nonterminalID == nonterminalIDFor!"BracedInitList")
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);

        skipToken(code, data, tree.childs[0]);

        bool hasDesignator;
        bool hasNonDesignator;
        void checkDesignator(Tree tree)
        {
            if (tree.nodeType == NodeType.array || tree.nodeType == NodeType.merged)
            {
                foreach (c; tree.childs)
                    checkDesignator(c);
            }
            else if (tree.nodeType == NodeType.nonterminal)
            {
                if (tree.nonterminalID == nonterminalIDFor!"InitializerClause")
                    hasNonDesignator = true;
                if (tree.nonterminalID == nonterminalIDFor!"InitializerClauseDesignator")
                    hasDesignator = true;
                if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
                {
                    foreach (c; tree.childs)
                        checkDesignator(c);
                }
            }
        }

        checkDesignator(tree.childs[1]);

        if (hasDesignator)
        {
            string lastLineIndent;
            getLastLineIndent(code, lastLineIndent);

            code.writeln("(){");
            code.write(data.options.indent, lastLineIndent);

            QualType t = semantic.extraInfo(parent).type;
            t.qualifiers &= ~Qualifiers.const_;

            ConditionMap!string codeType;
            code.writeln(typeToCode(t, data, condition, currentScope,
                    tree.location, [], codeType), " r;");
            code.write(data.options.indent, lastLineIndent);

            QualType currentType;
            void writeDesignatorList(Tree tree)
            {
                if (tree.nodeType == NodeType.array)
                {
                    foreach (c; tree.childs)
                        writeDesignatorList(c);
                }
                else if (tree.nodeType == NodeType.token)
                {
                    assert(false);
                }
                else if (tree.nodeType == NodeType.nonterminal)
                {
                    writeComments(code, data, tree.start);
                    if (tree.nameOrContent == "Designator" && tree.childs[0].nameOrContent == ".")
                    {
                        parseTreeToDCode(code, data, tree, condition, currentScope);
                    }
                    else if (tree.nameOrContent == "Designator"
                            && tree.childs[0].nameOrContent == "[")
                    {
                        parseTreeToDCode(code, data, tree, condition, currentScope);
                    }
                    else
                        assert(false);
                    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                            || tree.nodeType == NodeType.merged)
                    {
                        assert(false);
                    }
                }
            }

            void writeDesignators(Tree tree)
            {
                if (tree.nodeType == NodeType.array)
                {
                    foreach (c; tree.childs)
                        writeDesignators(c);
                }
                else if (tree.nodeType == NodeType.token)
                {
                    skipToken(code, data, tree);
                }
                else if (tree.nodeType == NodeType.nonterminal)
                {
                    writeComments(code, data, tree.start);
                    if (tree.nonterminalID == nonterminalIDFor!"InitializerClauseDesignator")
                    {
                        code.write("r");
                        currentType = t;
                        writeDesignatorList(tree.childs[0]);
                        currentType = QualType.init;
                        parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
                        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
                        code.write(";");
                    }
                    else if (tree.nonterminalID == nonterminalIDFor!"InitializerClause")
                    {
                        code.writeln("// TODO: mixed braced init list");
                    }
                    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                            || tree.nodeType == NodeType.merged)
                    {
                        code.writeln("// TODO: conditiontree");
                        foreach (c; tree.childs)
                            writeDesignators(c);
                    }
                    else
                        assert(false);
                }
            }

            writeDesignators(tree.childs[1]);

            code.writeln();
            code.write(data.options.indent, lastLineIndent);
            code.writeln("return r;");
            code.write(lastLineIndent);
            code.writeln("}()");
        }
        else
        {
            foreach (combination; iterateCombinations())
            {
                IteratePPVersions ppVersion = IteratePPVersions(combination,
                        semantic.logicSystem, condition);
                QualType t;
                if (parent.nonterminalID == nonterminalIDFor!"CompoundLiteralExpression")
                    t = chooseType(semantic.extraInfo(parent).type, ppVersion, true);
                else
                    t = chooseType(semantic.extraInfo2(tree).convertedType, ppVersion, true);

                if (t.type !is null && t.kind == TypeKind.array)
                {
                    auto atype = cast(ArrayType) t.type;
                    if (!atype.declarator.childs[2].isValid)
                    {
                        ConditionMap!string codeType;
                        codeWrapper.add("mixin(buildStaticArray!(q{" ~ typeToCode(atype.next, data, ppVersion.condition,
                                currentScope, tree.location, [], codeType) ~ "}, q{", "}))", ppVersion.condition);
                    }
                    else
                    {
                        bool goodSize;
                        ulong size;
                        if (atype.declarator.childs[2].nonterminalID == nonterminalIDFor!"Literal")
                        {
                            try
                            {
                                size = atype.declarator.childs[2].childs[0].content.to!ulong;
                                goodSize = true;
                            }
                            catch (Exception e)
                            {
                            }
                            if (tree.childs[1].nodeType != NodeType.array)
                                goodSize = false;
                            if (goodSize)
                            {
                                ulong literalSize = 0;
                                bool expectComma;
                                foreach (c; tree.childs[1].childs)
                                {
                                    if (expectComma)
                                    {
                                        if (c.nodeType != NodeType.token || c.content != ",")
                                        {
                                            goodSize = false;
                                            break;
                                        }
                                        expectComma = false;
                                    }
                                    else
                                    {
                                        if (c.nodeType != NodeType.nonterminal
                                                || c.nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                                                || c.nodeType == NodeType.merged)
                                        {
                                            goodSize = false;
                                            break;
                                        }
                                        literalSize++;
                                        expectComma = true;
                                    }
                                }
                                if (size != literalSize)
                                    goodSize = false;
                            }
                        }
                        if (!goodSize)
                        {
                            CodeWriter code2;
                            code2.indentStr = data.options.indent;
                            auto tokensLeftBak = data.sourceTokenManager.tokensLeft;
                            data.sourceTokenManager.tokensLeft = typeof(data.sourceTokenManager.tokensLeft)();
                            parseTreeToDCode(code2, data, atype.declarator.childs[2], ppVersion.condition, currentScope);
                            data.sourceTokenManager.tokensLeft = tokensLeftBak;
                            ConditionMap!string codeType;
                            codeWrapper.add("mixin(buildStaticArray!(q{" ~ typeToCode(atype.next,
                                    data, ppVersion.condition,
                                    currentScope, tree.location, [], codeType) ~ "}, " ~ code2.data.idup ~ ", q{",
                                    "}))", ppVersion.condition);
                        }
                        else
                        {
                            codeWrapper.add("[", "]", ppVersion.condition);
                        }
                    }
                }
                else if (t.type !is null && t.kind == TypeKind.record)
                {
                    ConditionMap!string codeType;
                    codeWrapper.add(typeToCode(t, data, ppVersion.condition, currentScope,
                            tree.location, [], codeType) ~ "(", ")", ppVersion.condition);
                }
                else
                {
                    codeWrapper.add("{", "}", ppVersion.condition);
                }
            }

            codeWrapper.checkTree(tree.childs[1 .. $ - 1], true);

            codeWrapper.begin(code, condition);

            if (codeWrapper.alwaysUseMixin)
            {
                void onTree(Tree t, immutable(Formula)* condition2)
                {
                    code.incIndent;
                    parseTreeToDCode(code, data, t, condition2, currentScope);
                    writeComments(code, data, data.sourceTokenManager.collectTokens(t.location.end));
                    writeComments(code, data,
                            data.sourceTokenManager.collectTokensUntilLineEnd(t.location.end, condition));
                    code.decIndent;
                }

                code.incIndent;
                codeWrapper.writeTree(code, &onTree, tree.childs[1 .. $ - 1]);
                code.decIndent;
            }
            else
            {
                foreach (c; tree.childs[1 .. $ - 1])
                {
                    parseTreeToDCode(code, data, c, condition, currentScope);
                }
            }

            codeWrapper.end(code, condition);
        }

        skipToken(code, data, tree.childs[$ - 1]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CommaExpression")
    {
        Tree nonExpr = tree;
        while (nonExpr.isValid && (nonExpr.nodeType != NodeType.nonterminal
                || nonExpr.name.endsWith("CommaExpression")))
            nonExpr = semantic.extraInfo(nonExpr).parent;

        if (nonExpr.isValid && (nonExpr.nameOrContent != "IterationStatementHead"
                || nonExpr.matchTreePattern!q{IterationStatementHead("while", ...)}))
        {
            parseTreeToCodeTerminal(code, "()");
            parseTreeToCodeTerminal(code, "{");
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope, TreeToCodeFlags.inStatementExpression);
            parseTreeToCodeTerminal(code, ";");
            code.writeln();
            skipToken(code, data, tree.childs[1]);
            parseTreeToCodeTerminal(code, "return");
            writeComments(code, data, tree.childs[2].start);
            if (code.data.length && !code.data[$ - 1].inCharSet!" \t")
                code.write(" ");
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
            parseTreeToCodeTerminal(code, ";");
            code.writeln();
            parseTreeToCodeTerminal(code, "}");
            parseTreeToCodeTerminal(code, "()");
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"AssignmentExpression")
    {
        Tree nonExpr = tree;
        while (nonExpr.isValid && (nonExpr.nodeType != NodeType.nonterminal
                || nonExpr.name.endsWith("Expression") || nonExpr.name.endsWith(
                "InitializerClause")))
            nonExpr = semantic.extraInfo(nonExpr).parent;
        if (tree.childs[1].childs[0].content == "=" && nonExpr.isValid
                && nonExpr.name != "ExpressionStatement" && !(parent.nameOrContent == "IterationStatementHead"
                    && parent.childs[0].nameOrContent == "for"
                    && parent.childs.length == 7 && indexInParent.among(2, 5))
                && !(parent.nonterminalID == nonterminalIDFor!"PrimaryExpression"
                    && parent2.nonterminalID.nonterminalIDAmong!("RelationalExpression",
                    "EqualityExpression")))
        {
            parseTreeToCodeTerminal(code, "()");
            parseTreeToCodeTerminal(code, "{");
            parseTreeToCodeTerminal(code, "return ");
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
            parseTreeToCodeTerminal(code, ";");
            code.writeln();
            parseTreeToCodeTerminal(code, "}");
            parseTreeToCodeTerminal(code, "()");
        }
        else if (semantic.extraInfo2(tree).acessingBitField
                && tree.childs[1].childs[0].content != "=")
        {
            Tree accessor = tree.childs[0];
            assert(accessor.nonterminalID == nonterminalIDFor!"PostfixExpression");
            assert(accessor.childs.length == 3 || accessor.childs.length == 4);
            parseTreeToDCode(code, data, accessor.childs[0], condition, currentScope);
            parseTreeToCodeTerminal(code, ".fallbackAssignExpression!(q{");
            skipToken(code, data, accessor.childs[1]);
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal(code, "}, q{");
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal(code, "})(");
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
            parseTreeToCodeTerminal(code, ")");
        }
        else if (tree.childs[1].childs[0].content == "+=")
        {
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            if (data.options.arrayLikeTypes.canFind(semantic.extraInfo(tree.childs[0]).type.name)
                || data.options.arrayLikeTypes.canFind(semantic.extraInfo(tree.childs[2]).type.name))
            {
                skipToken(code, data, tree.childs[1].childs[0]);
                code.write("~=");
            }
            else
                parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            PostfixExpression(*, "++" | "--")
        })
    {
        Tree next = tree.childs[0];
        while (next.nonterminalID == nonterminalIDFor!"PrimaryExpression" && next.childs.length == 3)
        {
            assert(next.childs[0].content == "(");
            assert(next.childs[2].content == ")");
            next = next.childs[1];
        }
        if (next.name != "NameIdentifier")
            next = tree.childs[0];

        if (semantic.extraInfo2(next).acessingBitField)
        {
            Tree accessor = next;
            assert(accessor.nonterminalID == nonterminalIDFor!"PostfixExpression");
            assert(accessor.childs.length == 3 || accessor.childs.length == 4);
            parseTreeToDCode(code, data, accessor.childs[0], condition, currentScope);
            parseTreeToCodeTerminal(code, ".fallbackPostfixExpression!(q{");
            skipToken(code, data, accessor.childs[1]);
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal(code, "}, q{");
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal(code, "})(");
            parseTreeToCodeTerminal(code, ")");
        }
        else
        {
            parseTreeToDCode(code, data, next, condition, currentScope);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("++" | "--", *)
        })
    {
        if (semantic.extraInfo2(tree.childs[1]).acessingBitField)
        {
            Tree accessor = tree.childs[1];
            assert(accessor.nonterminalID == nonterminalIDFor!"PostfixExpression");
            assert(accessor.childs.length == 3 || accessor.childs.length == 4);
            skipToken(code, data, tree.childs[0]);
            parseTreeToDCode(code, data, accessor.childs[0], condition, currentScope);
            skipToken(code, data, accessor.childs[1]);
            parseTreeToCodeTerminal(code, ".fallbackUnaryExpression!(q{");
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal(code, "}, q{");
            parseTreeToCodeTerminal(code, tree.childs[0].content);
            parseTreeToCodeTerminal(code, "})(");
            parseTreeToCodeTerminal(code, ")");
        }
        else
        {
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            PostfixExpression(PostfixExpression(*, "." | "->", PseudoDestructorName), "(", [], ")")
        })
    {
        code.write("destroy!false");
        if (tree.childs[0].childs[0].nameOrContent != "PrimaryExpression"
                || tree.childs[0].childs[0].childs[0].nameOrContent != "(")
            code.write("(");
        parseTreeToDCode(code, data, tree.childs[0].childs[0], condition, currentScope);
        if (tree.childs[0].childs[0].nameOrContent != "PrimaryExpression"
                || tree.childs[0].childs[0].childs[0].nameOrContent != "(")
            code.write(")");
        skipToken(code, data, tree.childs[0].childs[1], false, true);
        writeComments(code, data, tree.end, true);
    }
    else if (auto match = tree.matchTreePattern!q{
            PostfixExpression(*, "." | "->", ...)
        })
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition);
            Appender!string app;

            auto t = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);

            if (t.kind == TypeKind.array)
                app.put("[0]");

            app.put(".");

            void buildSuffix(Tree tree, ref IteratePPVersions ppVersion)
            {
                if (tree.nodeType == NodeType.token)
                {
                    if (tree.content.length)
                    {
                        app.put(replaceKeywords(tree.content));
                    }
                }
                else
                {
                    foreach (c; tree.childs)
                        iteratePPVersions!buildSuffix(c, ppVersion);
                }
            }

            foreach (c; tree.childs[2 .. $])
                iteratePPVersions!buildSuffix(c, ppVersion);

            codeWrapper.add("", app.data, ppVersion.condition);
        }

        codeWrapper.begin(code, condition);
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data, tree.childs[1].start);
        codeWrapper.end(code, condition);
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data, tree.end, true);
    }
    else if (auto match = tree.matchTreePattern!q{
            Designator(".", *)
        })
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        skipToken(code, data, tree.childs[1]);
        code.write(replaceKeywords(tree.childs[1].content));
    }
    else if (auto match = tree.matchTreePattern!q{
            PostfixExpression(*, "[", *, "]")
        })
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition);
            auto t = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);
            if (t.type !is null && t.kind == TypeKind.array)
            {
                auto atype = cast(ArrayType) t.type;
                if (atype.declarator.isValid && !atype.declarator.childs[2].isValid)
                {
                    codeWrapper.add("", ". ptr", ppVersion.condition);
                }
            }
        }

        codeWrapper.begin(code, condition);
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        codeWrapper.end(code, condition);
        foreach (c; tree.childs[1 .. $])
            parseTreeToDCode(code, data, c, condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"PostfixExpression"
            && tree.childs[1].nameOrContent.among("(") && tree.childs[0].nameOrContent != "typeid")
    {
        auto codeWrapper = ConditionalCodeWrapper(condition, data);
        auto codeWrapperInner = ConditionalCodeWrapper(condition, data);

        codeWrapper.forceExpression = parent.isValid
            && parent.nonterminalID.nonterminalIDAmong!("ArrayDeclarator", "ExpressionStatement");

        codeWrapper.checkTree(tree.childs[2], true);

        immutable(Formula)* needsCastHere = semantic.logicSystem.false_;
        immutable(Formula)* castPossibleHere = semantic.logicSystem.false_;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);

            Tree expr = ppVersion.chooseTree(tree.childs[2]);
            if (expr.nodeType == NodeType.array && expr.childs.length == 1)
                expr = expr.childs[0];

            auto toType1 = chooseType(semantic.extraInfo(tree.childs[0]).type, ppVersion, true);
            auto fromType1 = chooseType(semantic.extraInfo(expr).type, ppVersion, true);

            if (toType1.type is null || fromType1.type is null)
                continue;

            if (fromType1.kind == TypeKind.reference)
            {
                fromType1 = (cast(ReferenceType) fromType1.type).next.withExtraQualifiers(
                        fromType1.qualifiers);
            }

            if (toType1.kind == TypeKind.builtin && (toType1.qualifiers & Qualifiers.noThis) != 0)
            {
                auto toType = filterType(toType1, ppVersion.condition,
                        semantic, FilterTypeFlags.removeTypedef);
                auto fromType = filterType(fromType1, ppVersion.condition,
                        semantic, FilterTypeFlags.removeTypedef);

                castPossibleHere = semantic.logicSystem.or(castPossibleHere, ppVersion.condition);

                if (needsCast(toType, fromType, ppVersion, semantic))
                {
                    needsCastHere = semantic.logicSystem.or(needsCastHere, ppVersion.condition);
                }
            }

            Tree leftNameIdentifier = ppVersion.chooseTree(tree.childs[0]);
            while (leftNameIdentifier.isValid && leftNameIdentifier.nonterminalID.nonterminalIDAmong!("QualifiedId", "SimpleTypeSpecifierNoKeyword"))
                leftNameIdentifier = ppVersion.chooseTree(leftNameIdentifier.childs[$ - 1]);
            bool isToEnum;
            foreach (e; semantic.extraInfo(leftNameIdentifier).referenced.entries)
            {
                if (!isInCorrectVersion(ppVersion, e.condition))
                    continue;
                foreach (e2; e.data.entries)
                {
                    if (!isInCorrectVersion(ppVersion, e2.condition))
                        continue;
                    if (e2.data.tree.isValid && e2.data.tree.nonterminalID == nonterminalIDFor!"EnumSpecifier")
                        isToEnum = true;
                }
            }
            if (isToEnum && fromType1.kind == TypeKind.builtin)
            {
                castPossibleHere = semantic.logicSystem.or(castPossibleHere, ppVersion.condition);
                needsCastHere = semantic.logicSystem.or(needsCastHere, ppVersion.condition);
            }
        }
        if (!needsCastHere.isFalse)
        {
            if (semantic.logicSystem.and(condition, castPossibleHere.negated).isFalse)
                codeWrapperInner.add("cast(", ") ", castPossibleHere);
            else
                codeWrapperInner.add("cast(", ") ", needsCastHere);
        }

        if (codeWrapper.alwaysUseMixin)
        {
            codeWrapper.begin(code, condition);

            void onTree2(Tree t, immutable(Formula)* condition2)
            {
                code.incIndent;
                codeWrapperInner.begin(code, condition);
                parseTreeToDCode(code, data, t, condition2, currentScope);
                codeWrapperInner.end(code, condition);
                code.decIndent;
            }

            void onTree3(Tree t, immutable(Formula)* condition2)
            {
                code.incIndent;
                parseTreeToDCode(code, data, t, condition2, currentScope);
                code.decIndent;
            }

            code.incIndent;
            codeWrapper.writeTree(code, &onTree2, tree.childs[0]);
            skipToken(code, data, tree.childs[1]);
            codeWrapper.writeString(code, "(");
            codeWrapper.writeTree(code, &onTree3, tree.childs[2 .. $ - 1]);
            skipToken(code, data, tree.childs[3]);
            codeWrapper.writeString(code, ")");
            code.decIndent;

            codeWrapper.end(code, condition);
        }
        else
        {
            codeWrapperInner.begin(code, condition);
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            codeWrapperInner.end(code, condition);
            foreach (c; tree.childs[1 .. $])
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            JumpStatement2("goto", *)
        })
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        skipToken(code, data, tree.childs[1]);
        parseTreeToCodeTerminal(code, replaceKeywords(tree.childs[1].content));
    }
    else if (auto match = tree.matchTreePattern!q{
            PrimaryExpression("(", *, ")")
        })
    {
        bool needWrapper = parent.nonterminalID == nonterminalIDFor!"ExpressionStatement"
            && !tree.childs[1].nonterminalID.nonterminalIDAmong!("CastExpression",
                    "AssignmentExpression");
        if (needWrapper)
        {
            code.write("(){ return ");
            foreach (c; tree.childs)
                parseTreeToDCode(code, data, c, condition, currentScope);
            code.write("; }()");
        }
        else if (parent.nameOrContent == "PostfixExpression"
                && parent.childs[1].nameOrContent.among("(", "++", "--")
                && parent.childs[0].nameOrContent != "typeid" && parent.childs[0] is tree
                && tree.childs[1].nonterminalID.nonterminalIDAmong!("PostfixExpression", "NameIdentifier"))
        {
            parseTreeToCodeTerminal(code, "/*(*/");
            skipToken(code, data, tree.childs[0]);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal(code, "/*)*/");
            skipToken(code, data, tree.childs[2]);
        }
        else
        {
            foreach (c; tree.childs)
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NameIdentifier")
    {
        ConditionMap!string realId;

        ConditionMap!Declaration realDecl;
        findRealDecl(tree, realDecl, condition, data, true /*allowType*/ , currentScope);
        foreach (e; realDecl.entries)
        {
            if (e.data.flags & DeclarationFlags.templateSpecialization)
                continue;
            foreach (combination; iterateCombinations())
            {
                IteratePPVersions ppVersion = IteratePPVersions(combination,
                        semantic.logicSystem, logicSystem.and(e.condition, e.data.condition));

                Scope contextScope = getContextScope(tree, ppVersion, semantic, currentScope);

                immutable(Formula)* newCondition = ppVersion.condition;
                if (e.data.type != DeclarationType.namespace
                        && e.data.tree.nonterminalID == nonterminalIDFor!"Enumerator")
                {
                    ConditionMap!string codeType;
                    string declName = typeToCode(semantic.extraInfo(tree).type,
                            data, newCondition, contextScope, tree.location, [], codeType);

                    bool isEnumClass;
                    QualType enumType = chooseType(e.data.type2, ppVersion, true);
                    if (enumType.kind == TypeKind.record)
                    {
                        RecordType recordType = cast(RecordType) enumType.type;
                        foreach (e2; recordType.declarationSet.entries)
                            if (e2.data.flags & DeclarationFlags.enumClass)
                                isEnumClass = true;
                    }

                    if (declName != "" && !isEnumClass)
                    {
                        realId.add(newCondition,
                                declName ~ "." ~ replaceKeywords(tree.childs[0].content),
                                logicSystem);
                    }
                    else
                    {
                        string name = declarationNameToCode(e.data, data,
                                contextScope, newCondition);
                        if (e.data !in data.fileByDecl && realId.conditionAll !is null)
                            newCondition = logicSystem.and(newCondition,
                                    realId.conditionAll.negated);

                        realId.add(newCondition, name, logicSystem);
                    }
                }
                else if (e.data.type == DeclarationType.type
                        && (e.data.flags & DeclarationFlags.typedef_) != 0
                        && isSelfTypedef(e.data, data))
                {
                    QualType type = semantic.extraInfo(tree).type;
                    if (type.kind == TypeKind.function_)
                        type = (cast(FunctionType) type.type).resultType;
                    ConditionMap!string codeType;
                    CodeWriter codeAfterDeclSeq;
                    bool afterTypeInDeclSeq;
                    collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                            afterTypeInDeclSeq, tree, ppVersion.condition, data, currentScope);
                    string name = typeToCode(type, data, newCondition,
                            contextScope, tree.location, [], codeType);
                    realId.addReplace(newCondition, name ~ codeAfterDeclSeq.data.idup, logicSystem);
                }
                else
                {
                    string name = declarationNameToCode(e.data, data, contextScope, newCondition);
                    if (e.data !in data.fileByDecl && realId.conditionAll !is null)
                        newCondition = logicSystem.and(newCondition, realId.conditionAll.negated);
                    realId.addReplace(newCondition, name, logicSystem);
                }
            }
        }

        realId.removeFalseEntries();

        if (realId.entries.length == 0)
        {
            parseTreeToCodeTerminal(code, replaceKeywords(tree.childs[0].content));
        }
        else if (realId.entries.length == 1)
        {
            parseTreeToCodeTerminal(code, realId.entries[0].data);
        }
        else
        {
            code.writeln();
            foreach (i, e; realId.entries)
            {
                if (i == 0)
                    code.write("mixin(");
                else
                    code.write(" : ");
                if (i < realId.entries.length - 1)
                    code.write(conditionToDCode(e.condition, data), " ? ");
                code.write("q{", e.data, "}");
            }
            code.write(")");
        }

        skipToken(code, data, tree.childs[0]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"SimpleTemplateId")
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        code.write("!(");
        skipToken(code, data, tree.childs[1]);
        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
        code.write(")");
        skipToken(code, data, tree.childs[3]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"StaticAssertDeclarationX")
    {
        skipToken(code, data, tree.childs[0]);
        code.write("static assert");
        foreach (c; tree.childs[1 .. $])
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"EnumKey")
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ClassKey")
    {
        Tree specifier;
        if (parent.nonterminalID == nonterminalIDFor!"ClassHead")
        {
            assert(parent2.nonterminalID == nonterminalIDFor!"ClassSpecifier", text(parent2));
            specifier = parent2;
        }
        else
        {
            assert(parent.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier", text(parent));
            specifier = parent;
        }

        if (isStruct(specifier, data))
        {
            skipToken(code, data, tree.childs[0]);
            if (tree.childs[0].content == "class")
                code.write("extern(C++, class) ");
            code.write("struct");
        }
        else if (isClass(specifier, data))
        {
            skipToken(code, data, tree.childs[0]);
            if (tree.childs[0].content == "struct")
                code.write("extern(C++, struct) ");
            code.write("class");
        }
        else
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"BaseSpecifier")
    {
        assert(parent.nonterminalID == nonterminalIDFor!"BaseClause");
        assert(parent2.nonterminalID == nonterminalIDFor!"ClassHead");
        assert(parent3.nonterminalID == nonterminalIDFor!"ClassSpecifier");
        if (parent2.childs[0].nonterminalID == nonterminalIDFor!"ClassKey" && isStruct(parent3, data))
        {
            CodeWriter code2;
            code2.indentStr = data.options.indent;
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code2, data, c, condition, currentScope);
            }
            data.declarationData(data.currentDeclaration)
                .structBaseclasses.add(condition, code2.data.idup, logicSystem);
        }
        else
        {
            bool hasAccessSpecifier;
            foreach (c; tree.childs[0 .. $ - 1])
            {
                if (c.nameOrContent == "AccessSpecifier")
                {
                    if (c.childs[0].content == "public")
                    {
                        skipToken(code, data, c.childs[0], false, true);
                        hasAccessSpecifier = true;
                    }
                }
            }
            if (!hasAccessSpecifier)
            {
                writeComments(code, data, tree.childs[$ - 1].start);
                code.write("/+ private +/ ");
            }
            parseTreeToDCode(code, data, tree.childs[$ - 1], condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"BaseClause")
    {
        assert(parent.nonterminalID == nonterminalIDFor!"ClassHead");
        assert(parent2.nonterminalID == nonterminalIDFor!"ClassSpecifier");
        if (parent.childs[0].nonterminalID == nonterminalIDFor!"ClassKey" && isStruct(parent2, data))
        {
            SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.start, false);
            while (tokens.length && tokens[$ - 1].isWhitespace
                    && tokens[$ - 1].token.content.startsWith(" "))
                tokens = tokens[0 .. $ - 1];
            writeComments(code, data, tokens);

            skipToken(code, data, tree.childs[0], false, true);

            tokens = data.sourceTokenManager.collectTokens(tree.childs[1].start, false);
            while (tokens.length && tokens[0].isWhitespace && tokens[0].token.name.startsWith(" "))
                tokens = tokens[1 .. $];
            writeComments(code, data, tokens);

            foreach (c; tree.childs[1].childs)
            {
                if (c.nodeType == NodeType.token)
                    skipToken(code, data, c, false, true);
                else
                    parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"PointerLiteral")
    {
        skipToken(code, data, tree.childs[0]);
        code.write("null");
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NestedNameSpecifier")
    {
        bool isNestedNameRedundant = true;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            QualType nsType = chooseType(semantic.extraInfo(tree).type, ppVersion, true);
            Scope nsScope;
            if (nsType.kind.among(TypeKind.namespace, TypeKind.record))
                nsScope = scopeForRecord(nsType.type, ppVersion, semantic);

            Scope realScope = currentScope;
            if (currentScope !is null)
            {
                foreach (e; currentScope.extraParentScopes.entries)
                {
                    if (e.data.type != ExtraScopeType.namespace)
                        continue;
                    if (!isInCorrectVersion(ppVersion, e.condition))
                        continue;
                    realScope = e.data.scope_;
                    break;
                }
            }

            if (realScope !is nsScope)
            {
                isNestedNameRedundant = false;
            }
        }
        if (isNestedNameRedundant)
        {
            writeComments(code, data, tree.end, true);
            return;
        }

        if (tree.childs.length >= 2)
        {
            if (semantic.extraInfo(tree.childs[$ - 2]).type.kind == TypeKind.namespace)
                return;
        }
        foreach (i, c; tree.childs)
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"AccessSpecifierAnnotation")
    {
    }
    else if (auto match = tree.matchTreePattern!q{
            PostfixExpression(*, "<", *, ">", "(", *, ")")
        })
    {
        foreach (i, c; tree.childs)
        {
            if (i == 1)
            {
                skipToken(code, data, c);
                code.write("!(");
            }
            else if (i == 3)
            {
                skipToken(code, data, c);
                code.write(")");
            }
            else
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            PrimaryExpression("this")
        })
    {
        skipToken(code, data, tree.childs[0]);
        if (parent.isValid && parent.nameOrContent == "PostfixExpression"
                && indexInParent == 0 && parent.childs[1].nameOrContent.among(".", "->"))
            code.write("this");
        else if (data.currentClassDeclaration !is null
                && !isClass(data.currentClassDeclaration.tree, data))
            code.write("&this");
        else
            code.write("this");
    }
    else if (auto match = tree.matchTreePattern!q{
            UnaryExpression("*", *)
        })
    {
        if (tree.childs[1].nameOrContent == "PrimaryExpression"
                && tree.childs[1].childs[0].nameOrContent == "this" && data.currentClassDeclaration !is null
                && !isClass(data.currentClassDeclaration.tree, data))
        {
            skipToken(code, data, tree.childs[0]);
            skipToken(code, data, tree.childs[1].childs[0]);
            code.write("this");
        }
        else
        {
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            ExpressionStatement(PostfixExpression(*, "(", *, ")"), ";")
        })
    {
        Tree lhs = tree.childs[0].childs[0];
        while (lhs.nameOrContent == "PostfixExpression"
                && lhs.childs[1].nameOrContent.among(".", "->"))
            lhs = lhs.childs[$ - 1];

        if (isPostfixExpressionWithRValueRefs(tree.childs[0], data)
                && !(lhs.nonterminalID == nonterminalIDFor!"NameIdentifier"
                    && lhs.childs[0].content.among("setText", "setItemText",
                    "setWindowTitle", "setObjectName", "setPlainText", "setShortcut",
                    "setTitle", "addItem", "setTabText", "addTab",
                    "setHtml", "setStatusTip", "setToolTip", "setWhatsThis",
                    "setMarkdown", "appendPlainText")))
        {
            CodeWriter code2;
            code2.indentStr = data.options.indent;

            Tree parentStatement = parent;
            assert(parentStatement.nonterminalID == nonterminalIDFor!"Statement",
                    text(parentStatement.name, " ", locationStr(tree.location)));
            parentStatement = getRealParent(parentStatement, semantic);

            if (parentStatement.name != "CompoundStatement")
                code.write("{ ");

            writePostfixExpressionWithRValueRefs(code, code2, data,
                    tree.childs[0], condition, currentScope);
            code.write(code2.data);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope); // ;
            if (parentStatement.name != "CompoundStatement")
                code.write("}");
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (auto match = tree.matchTreePattern!q{
            JumpStatement(JumpStatement2("return", PostfixExpression(*, "(", *, ")")), ";")
        })
    {
        if (isPostfixExpressionWithRValueRefs(tree.childs[0].childs[1], data))
        {
            CodeWriter code2;
            code2.indentStr = data.options.indent;

            Tree parentStatement = parent;
            assert(parentStatement.nonterminalID == nonterminalIDFor!"Statement",
                    text(parentStatement.name, " ", locationStr(tree.location)));
            parentStatement = getRealParent(parentStatement, semantic);

            if (parentStatement.name != "CompoundStatement")
                code.write("{ ");

            parseTreeToDCode(code2, data, tree.childs[0].childs[0], condition, currentScope);
            writePostfixExpressionWithRValueRefs(code, code2, data,
                    tree.childs[0].childs[1], condition, currentScope);
            code.write(code2.data);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope); // ;
            if (parentStatement.name != "CompoundStatement")
                code.write("}");
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (auto match = tree.matchTreePattern!q{
        TryBlock("try", CompoundStatement, [
                h = Handler(CatchHead("catch", "(", ExceptionDeclaration("..."), ")"),
                    c = CompoundStatement("{", [..., s = Statement(*, ExpressionStatement(ThrowExpression("throw", null), ";"))], "}")
                )
            ]
        )
        })
    {
        skipToken(code, data, tree.childs[0], false, true);

        Scope currentScope2 = currentScope;
        if (currentScope2 !is null && tree.childs[1] in currentScope2.childScopeByTree)
            currentScope2 = currentScope2.childScopeByTree[tree.childs[1]];
        Scope currentScope3 = currentScope;
        if (currentScope3 !is null
                && match.savedc in currentScope3.childScopeByTree)
            currentScope3 = currentScope3.childScopeByTree[match.savedc];

        parseTreeToDCode(code, data, tree.childs[1].childs[0], condition, currentScope2); // {
        writeComments(code, data,
                data.sourceTokenManager.collectTokensUntilLineEnd(tree.childs[1].childs[0].end,
                    condition));

        CodeWriter code2;
        code2.indentStr = data.options.indent;
        parseTreeToDCode(code2, data, tree.childs[1].childs[1], condition, currentScope2);
        parseTreeToDCode(code2, data, tree.childs[1].childs[2], condition, currentScope2); // }
        writeComments(code, data,
                data.sourceTokenManager.collectTokensUntilLineEnd(tree.childs[1].childs[2].end,
                    condition));

        CodeWriter code3;
        code3.indentStr = data.options.indent;
        code3.incIndent;
        if (code2.inLine)
        {
            string indent;
            getLastLineIndent(code2, indent);
            code3.write(indent);
        }
        skipToken(code3, data, match.savedh.childs[0].childs[0], false, true); // catch
        code3.write("scope(failure)");
        skipToken(code3, data, match.savedh.childs[0].childs[1], false, true); // (
        skipToken(code3, data, match.savedh.childs[0].childs[2].childs[0], false, true); // ...
        skipToken(code3, data, match.savedh.childs[0].childs[3], false, true); // )
        parseTreeToDCode(code3, data,
                match.savedc.childs[0], condition, currentScope3); // {
        foreach (c; match.savedc.childs[1].childs[0 .. $ - 1])
        {
            parseTreeToDCode(code3, data, c, condition, currentScope3);
            writeComments(code3, data,
                    data.sourceTokenManager.collectTokensUntilLineEnd(c.end, condition));
        }

        data.sourceTokenManager.collectTokens(
                match.saveds.end);
        data.sourceTokenManager.collectTokensUntilLineEnd(
                match.saveds.end, condition);

        parseTreeToDCode(code3, data,
                match.savedc.childs[2], condition, currentScope3); // }
        code3.decIndent;

        code.writeln(code3.data);
        code.write(code2.data);
    }
    else if (auto match = tree.matchTreePattern!q{
            DeleteExpression(*, "delete", *)
        })
    {
        skipToken(code, data, tree.childs[1], false, true);
        code.write("cpp_delete(");
        parseTreeToDCode(code, data, tree.childs[$ - 1], condition, currentScope);
        code.write(")");
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NewExpression" && !tree.childs[2].isValid)
    {
        skipToken(code, data, tree.childs[1], false, true);
        code.write("cpp_new!");
        if (tree.childs.length == 7)
        {
            foreach (c; tree.childs[3 .. $ - 1])
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
        else
        {
            bool needsParens = !tree.childs[3].matchTreePattern!q{
                NewTypeId([NameIdentifier | TypeKeyword], null)
            };
            if (needsParens)
                code.write("(");
            parseTreeToDCode(code, data, tree.childs[3], condition, currentScope);
            if (needsParens)
                code.write(")");
        }
        parseTreeToDCode(code, data, tree.childs[$ - 1], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NewExpression" && tree.childs[2].isValid)
    {
        skipToken(code, data, tree.childs[1], false, true);
        code.write("emplace!");
        CodeWriter code2;
        enforce(tree.childs[2].nonterminalID == nonterminalIDFor!"NewPlacement");
        skipToken(code2, data, tree.childs[2].childs[0]);
        parseTreeToDCode(code2, data, tree.childs[2].childs[1], condition, currentScope);
        skipToken(code2, data, tree.childs[2].childs[2]);

        if (data.sourceTokenManager.tokensLeft.data.length)
        {
            SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.childs[3].start,
                    false);
            while (tokens.length && tokens[$ - 1].isWhitespace
                    && (tokens[$ - 1].token.content.startsWith(" ")
                        || tokens[$ - 1].token.content.startsWith("\t")))
                tokens = tokens[0 .. $ - 1];
            writeComments(code, data, tokens);
        }

        if (tree.childs.length == 7)
        {
            foreach (c; tree.childs[3 .. $ - 1])
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
        else
        {
            parseTreeToDCode(code, data, tree.childs[3], condition, currentScope);
        }
        if (tree.childs[$ - 1].isValid)
        {
            enforce(tree.childs[$ - 1].nonterminalID == nonterminalIDFor!"NewInitializer");
            parseTreeToDCode(code, data, tree.childs[$ - 1].childs[0], condition, currentScope);
            code.write(code2.data);
            if (tree.childs[$ - 1].childs[1].isValid && tree.childs[$ - 1].childs[1].childs.length)
            {
                code.write(", ");
                parseTreeToDCode(code, data, tree.childs[$ - 1].childs[1], condition, currentScope);
            }
            parseTreeToDCode(code, data, tree.childs[$ - 1].childs[2], condition, currentScope);
        }
        else
        {
            code.write("(");
            code.write(code2.data);
            code.write(")");
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"EqualityExpression")
    {
        bool useIs = (tree.childs[0].nonterminalID == nonterminalIDFor!"PointerLiteral"
                && tree.childs[0].childs[0].content.endsWith("nullptr"))
            || (tree.childs[2].nonterminalID == nonterminalIDFor!"PointerLiteral"
                    && tree.childs[2].childs[0].content.endsWith("nullptr"));
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        if (useIs)
        {
            skipToken(code, data, tree.childs[1]);
            if (tree.childs[1].content == "==")
                parseTreeToCodeTerminal(code, "is");
            else if (tree.childs[1].content == "!=")
                code.write("!is");
            else
                assert(false);
        }
        else
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"AdditiveExpression")
    {
        parseTreeToDCode(code, data, tree.childs[0], condition, currentScope);
        if (tree.childs[1].content == "+"
            && (data.options.arrayLikeTypes.canFind(semantic.extraInfo(tree.childs[0]).type.name)
                || data.options.arrayLikeTypes.canFind(semantic.extraInfo(tree.childs[2]).type.name)))
        {
            skipToken(code, data, tree.childs[1]);
            code.write("~");
        }
        else
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
        parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
    }
    else if (auto match = tree.matchTreePattern!q{
            OperatorFunctionId(*, OverloadableOperator)
        })
    {
        string opName;
        if (tree.childs[1].childs.length == 2
                && tree.childs[1].childs[0].content == "["
                && tree.childs[1].childs[1].content == "]")
            opName = "opIndex";
        if (opName.length)
        {
            skipToken(code, data, tree, true);
            code.write(opName);
        }
        else
        {
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"IterationStatementHead" && tree.childs.length == 6)
    {
        foreach (i, c; tree.childs)
        {
            if (i == 0)
            {
                assert(c.content == "for");
                skipToken(code, data, c);
                code.write("foreach");
            }
            else if (i == 3)
            {
                assert(c.content == ":");
                skipToken(code, data, c, false, true);
                code.write(";");
            }
            else
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"LambdaIntroducer")
    {
    }
    else
    {
        foreach (c; tree.childs)
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
        }
    }
}
