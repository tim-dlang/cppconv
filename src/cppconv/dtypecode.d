
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dtypecode;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.dwriter;
import cppconv.locationstack;
import cppconv.logic;
import cppconv.macrodeclaration;
import cppconv.preproc;
import cppconv.sourcetokens;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.stdio;

void collectDeclSeqTokensImpl(ref CodeWriter code, Tree tree, ref IteratePPVersions ppVersion,
        DWriterData data, Scope currentScope, bool inPath, ref bool needsValueClass)
{
    auto semantic = data.semantic;
    if (!tree.isValid || tree.nodeType != NodeType.nonterminal)
        return;
    writeComments(code, data, data.sourceTokenManager.collectTokens(tree.start), false);
    auto logicSystem = semantic.logicSystem;
    if (tree.nonterminalID.nonterminalIDAmong!("SimpleTypeSpecifierNoKeyword"))
    {
        foreach (i, c; tree.childs)
            collectDeclSeqTokensImpl(code, c, ppVersion, data, currentScope,
                    inPath, needsValueClass);

        writeComments(code, data, data.sourceTokenManager.collectTokens(tree.end), true);
    }
    if (tree.nonterminalID.nonterminalIDAmong!("TypenameSpecifier"))
    {
        skipToken(code, data, tree.childs[0], false, true);
        foreach (c; tree.childs[1 .. $])
            collectDeclSeqTokensImpl(code, c, ppVersion, data, currentScope,
                    inPath, needsValueClass);

        writeComments(code, data, data.sourceTokenManager.collectTokens(tree.end), true);
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("NestedNameSpecifier"))
    {
        if (tree.childs.length >= 2)
        {
            if (semantic.extraInfo(tree.childs[$ - 2]).type.kind == TypeKind.namespace)
                return;

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

            if (realScope is nsScope)
            {
                writeComments(code, data, tree.end, true);
                return;
            }

            foreach (c; tree.childs)
                collectDeclSeqTokensImpl(code, c, ppVersion, data,
                        currentScope, true, needsValueClass);
            writeComments(code, data,
                    data.sourceTokenManager.collectTokens(tree.childs[$ - 1].start), true);
            skipToken(code, data, tree.childs[$ - 1]);
            code.write(".");
            writeComments(code, data, data.sourceTokenManager.collectTokens(tree.end), true);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("NestedNameSpecifierHead"))
    {
        foreach (c; tree.childs)
            collectDeclSeqTokensImpl(code, c, ppVersion, data,
                    currentScope, true, needsValueClass);
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("TypeKeyword", "ElaboratedTypeSpecifier",
            "ClassSpecifier", "EnumSpecifier", "NameIdentifier", "SimpleTemplateId"))
    {
        LocationRangeX currentLoc = tree.location;

        auto type = chooseType(semantic.extraInfo(tree).type, ppVersion, false);

        Declaration d;
        if (type.kind.among(TypeKind.record, TypeKind.typedef_))
        {
            RecordType recordType = cast(RecordType) type.type;

            ConditionMap!Declaration realDecl;
            findRealDecl(recordType.declarationSet, type.kind == TypeKind.typedef_,
                    realDecl, tree.location, ppVersion.condition, data, currentScope);
            d = realDecl.choose(ppVersion);
        }

        Scope contextScope = currentScope;
        if (tree.nonterminalID == nonterminalIDFor!"NameIdentifier")
        {
            contextScope = getContextScope(tree, ppVersion, semantic, currentScope);
        }

        if (tree.nonterminalID.nonterminalIDAmong!("ClassSpecifier", "EnumSpecifier"))
        {
            data.sourceTokenManager.collectTokens(tree.end);
        }

        if (d is null)
        {
            if (tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier")
            {
                data.sourceTokenManager.collectTokens(tree.childs[$ - 1].start);
                foreach (c; tree.childs[$ - 1 .. $])
                    parseTreeToDCode(code, data, c, ppVersion.condition, currentScope);
            }
            else if (tree.nonterminalID == nonterminalIDFor!"NameIdentifier")
                code.write(tree.childs[0].content);
            else if (tree.nonterminalID == nonterminalIDFor!"TypeKeyword")
                code.write("$builtin_", tree.childs[0].content);
            else
                parseTreeToDCode(code, data, tree, ppVersion.condition, currentScope);

            writeComments(code, data, data.sourceTokenManager.collectTokens(tree.end), true);
            return;
        }

        Declaration d2 = getSelfTypedefTarget(d, data);
        if (d2 !is null)
            d = d2;

        if (d in data.forwardDecls)
            if (!isInCorrectVersion(ppVersion, data.forwardDecls[d].negated))
                return;
        string name = declarationNameToCode(d, data, contextScope, ppVersion.condition);

        if (tree.nonterminalID == nonterminalIDFor!"SimpleTemplateId")
        {
            data.sourceTokenManager.collectTokens(tree.childs[0].end);
            CodeWriter code2;
            code2.indentStr = data.options.indent;
            skipToken(code, data, tree.childs[1]);
            code2.write("!(");
            foreach (c; tree.childs[$ - 2 .. $ - 1])
                parseTreeToDCode(code2, data, c, ppVersion.condition, currentScope);
            skipToken(code, data, tree.childs[3]);
            code2.write(")");
            name ~= code2.data;
        }

        needsValueClass = !inPath && d.type != DeclarationType.builtin && isClass(d.tree, data) /* && (flags & TypeToCodeFlags.insideSkippedPointer) == 0*/ ;
        code.write(name);
        writeComments(code, data, data.sourceTokenManager.collectTokens(tree.end), true);
    }
}

void collectDeclSeqTokens(ref CodeWriter code, ref ConditionMap!string codeType, ref CodeWriter codeAfterDeclSeq,
        ref bool afterTypeInDeclSeq, Tree tree, immutable(Formula)* condition,
        DWriterData data, Scope currentScope)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    if (!tree.isValid)
        return;

    if (tree in data.macroReplacement)
    {
        CodeWriter code2;

        auto instance = data.macroReplacement[tree];
        if (tree !is instance.firstUsedTree)
            return;
        bool needsParens = false;

        string name = instance.usedName;

        name = qualifyName(name, instance.macroDeclaration, data, currentScope, condition);

        if (instance.macroDeclaration.type == DeclarationType.macroParam)
        {
            if (instance.macroTranslation == MacroTranslation.enumValue)
            {
                code2.write(instance.usedName);
            }
            else if (instance.macroTranslation == MacroTranslation.alias_)
            {
                code2.write(instance.usedName);
            }
            else if (instance.hasParamExpansion)
            {
                code2.write("$(stringifyMacroParameter(", instance.usedName, "))");
            }
            else
                code2.write("$(", instance.usedName, ")");
            if (data.sourceTokenManager.tokensLeft.data.length)
                data.sourceTokenManager.collectTokens(tree.location.end);
        }
        else if (instance.macroTranslation.among(MacroTranslation.enumValue,
                MacroTranslation.mixin_, MacroTranslation.alias_, MacroTranslation.builtin))
        {
            if (code2.inLine && code2.data.length
                    && !code2.data[$ - 1].inCharSet!" \t" && !code2.data.endsWith("("))
                code2.write(" ");

            string macroSuffix;
            if (instance.macroTranslation.among(MacroTranslation.enumValue,
                    MacroTranslation.builtin))
            {
            }
            else if (instance.macroTranslation == MacroTranslation.mixin_)
            {
                if (tree.nonterminalID == nonterminalIDFor!"TypeId")
                {
                    code2.write("Identity!(");
                    macroSuffix = ")" ~ macroSuffix;
                }
                code2.write("mixin(");
                macroSuffix = ")" ~ macroSuffix;
            }
            parseTreeToCodeTerminal!Tree(code2, name);

            assert(instance.locationContextInfo.locationContext.name == "^");
            assert(instance.locationContextInfo.locationContext.prev.name
                    == instance.locationContextInfo.locationContext.prev.prev.name);
            bool allowComments = instance.locationContextInfo.locationContext.prev.prev.prev.name == ""
                || instance.locationContextInfo.locationContext.prev.prev.prev is data.sourceTokenManager.tokensContext;

            parseTreeToCodeTerminal!Tree(code2, macroSuffix);
            if (data.sourceTokenManager.tokensLeft.data.length && allowComments)
                data.sourceTokenManager.collectTokens(tree.location.end);
        }

        codeType.addCombine!((a, b) => a ~ b)(condition, code2.data.idup, logicSystem);

        return;
    }

    if (tree.nonterminalID.nonterminalIDAmong!("DeclSpecifierSeq"))
    {
        collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                afterTypeInDeclSeq, tree.childs[0], condition, data, currentScope);
        return;
    }
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
            collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                    afterTypeInDeclSeq, c, condition, data, currentScope);
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);
        foreach (i, c; tree.childs)
            collectDeclSeqTokens(code, codeType, codeAfterDeclSeq, afterTypeInDeclSeq, c,
                    semantic.logicSystem.and(condition, ctree.conditions[i]), data, currentScope);
    }
    writeComments(afterTypeInDeclSeq ? codeAfterDeclSeq : code, data,
            data.sourceTokenManager.collectTokens(tree.start), false);
    if (tree.nonterminalID.nonterminalIDAmong!("TypeKeyword",
            "ElaboratedTypeSpecifier", "ClassSpecifier", "EnumSpecifier",
            "NameIdentifier", "SimpleTemplateId",
            "SimpleTypeSpecifierNoKeyword", "TypenameSpecifier"))
    {
        ConditionMap!string codeType2;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition);
            CodeWriter code2;
            bool needsValueClass;
            collectDeclSeqTokensImpl(code2, tree, ppVersion, data,
                    currentScope, false, needsValueClass);
            writeComments(code2, data, data.sourceTokenManager.collectTokens(tree.end), false);
            string name = code2.data.idup;
            while (name.endsWith(" "))
                name = name[0 .. $ - 1];
            if (needsValueClass)
            {
                name = "ValueClass!(" ~ name ~ ")";
            }

            codeType2.addReplace(ppVersion.condition, name, logicSystem);
        }
        foreach (e; codeType2.entries)
            codeType.addCombine!((a, b) => a ~ b)(e.condition, e.data, logicSystem);

        afterTypeInDeclSeq = true;
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("DeclSpecifierTypedef")
            || (tree.nameOrContent == "CvQualifier" && tree.childs[0].nameOrContent == "const")
            || (tree.nameOrContent == "StorageClassSpecifier"
                && tree.childs[0].nameOrContent.among("extern", "static")))
    {
        skipToken(code, data, tree.childs[0], false, true);
    }
    else if (tree.nameOrContent == "FunctionSpecifier"
            && tree.childs[0].nameOrContent.startsWith("inline"))
    {
        skipToken(code, data, tree.childs[0], false, true);
    }
    else if (tree.nameOrContent == "DeclSpecifier"
            && tree.childs[0].nameOrContent.startsWith("constexpr"))
    {
        skipToken(code, data, tree.childs[0], false, true);
    }
    else if (tree.nameOrContent == "AttributeSpecifier"
            && tree.childs[0].nameOrContent.startsWith("__cppconv_qt_"))
    {
        skipToken(code, data, tree.childs[0]);
        /*if (tree.childs[0].name == "__cppconv_qt_slot")
            code.write("@QSlot");
        else if (tree.childs[0].name == "__cppconv_qt_signal")
            code.write("@QSignal");
        else if (tree.childs[0].name == "__cppconv_qt_invokable")
            code.write("@QInvokable");
        else assert(0);*/
    }
    else
        writeComments(afterTypeInDeclSeq ? codeAfterDeclSeq : code, data,
                data.sourceTokenManager.collectTokens(tree.end), false);
}

struct DeclaratorData
{
    Tree tree;
    string codeBefore;
    string codeMiddle;
    string codeAfter;
}

DeclaratorData[] declaratorList(Tree declarator, immutable(Formula)* condition,
        DWriterData data, Scope currentScope, bool isStructConstructor = false)
{
    auto semantic = data.semantic;
    DeclaratorData[] r;
    void visitDeclarator(Tree declarator)
    {
        if (!declarator.isValid)
        {
            return;
        }
        if (declarator.nonterminalID == nonterminalIDFor!"DeclaratorId"
                || (declarator.nonterminalID == nonterminalIDFor!"NoptrDeclarator"
                    && declarator.childs.length == 2)
                || declarator.nonterminalID == nonterminalIDFor!"FakeAbstractDeclarator")
        {
            data.sourceTokenManager.collectTokens(declarator.end);
            return;
        }

        if (declarator.nodeType == NodeType.merged)
        {
            auto mdata = &semantic.mergedTreeData(declarator);
            if (semantic.logicSystem.and(mdata.mergedCondition, condition).isFalse)
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
                    visitDeclarator(declarator.childs[index]);
                    return;
                }
            }

            return;
        }
        assert(declarator.nodeType != NodeType.merged);
        if (declarator.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            auto ctree = declarator.toConditionTree;
            assert(ctree !is null);
            size_t index;
            size_t numPossible;
            foreach (i, c; declarator.childs)
            {
                if (!semantic.logicSystem.and(condition, ctree.conditions[i]).isFalse)
                {
                    numPossible++;
                    index = i;
                }
            }
            if (numPossible == 1)
            {
                visitDeclarator(declarator.childs[index]);
            }
            return;
        }

        DeclaratorData declaratorData;
        CodeWriter codeBefore;
        codeBefore.indentStr = data.options.indent;
        CodeWriter codeMiddle;
        codeMiddle.indentStr = data.options.indent;
        CodeWriter codeAfter;
        codeAfter.indentStr = data.options.indent;
        codeMiddle.inLine = true;
        codeAfter.inLine = true;
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(codeBefore, data,
                    data.sourceTokenManager.collectTokens(declarator.start));
        declaratorData.tree = declarator;

        if ((declarator.nonterminalID == nonterminalIDFor!"NoptrDeclarator" && declarator.childs.length == 4)
                || declarator.nonterminalID == nonterminalIDFor!"NoptrAbstractDeclarator")
        {
            assert(declarator.childs[0].content == "(");
            skipToken(codeBefore, data, declarator.childs[0]);
            Tree c = declarator.childByName("innerDeclarator");
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(codeBefore, data, data.sourceTokenManager.collectTokens(c.start));
            visitDeclarator(c);
            assert(declarator.childs[$ - 1].content == ")");
            skipToken(codeBefore, data, declarator.childs[$ - 1]);
        }
        else if (declarator.nonterminalID.nonterminalIDAmong!("PtrDeclarator",
                "PtrAbstractDeclarator"))
        {
            Tree c = declarator.childByName("innerDeclarator");
            if (declarator.childs[0].childs[0].nameOrContent.among("*", "&"))
            {
                skipToken(codeBefore, data, declarator.childs[0].childs[0]);
                if (c.isValid && data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(codeAfter, data, data.sourceTokenManager.collectTokens(c.start));
            }
            else
            {
                if (c.isValid && data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(codeBefore, data,
                            data.sourceTokenManager.collectTokens(c.start));
            }
            visitDeclarator(c);
        }
        else if (declarator.nonterminalID.nonterminalIDAmong!("ArrayDeclarator",
                "ArrayAbstractDeclarator"))
        {
            Tree c = declarator.childByName("innerDeclarator");
            if (c.isValid)
            {
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(codeBefore, data,
                            data.sourceTokenManager.collectTokens(c.start));
                visitDeclarator(c);
            }
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(codeAfter, data,
                        data.sourceTokenManager.collectTokens(declarator.childs[1].start));
            skipToken(codeBefore, data, declarator.childs[1]);
            codeBefore.write("[");
            data.afterStringLiteral = false;
            parseTreeToDCode(codeBefore, data, declarator.childs[2], condition, currentScope);
            if (!declarator.childs[2].isValid)
                codeBefore.write("0");
            skipToken(codeBefore, data, declarator.childs[4]);
            codeBefore.write("]");
        }
        else if (declarator.nonterminalID.nonterminalIDAmong!("FunctionDeclarator",
                "FunctionAbstractDeclarator"))
        {
            Tree c = declarator.childByName("innerDeclarator");
            if (c.isValid)
            {
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(codeBefore, data,
                            data.sourceTokenManager.collectTokens(c.start));
                visitDeclarator(c);
            }
            if (declarator.childs[1].nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                || declarator.childs[1].childs[0].nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                codeAfter.write("/+TODO: ParametersAndQualifiers ConditionTree+/");
            }
            else
            {
                assert(declarator.childs[1].nonterminalID == nonterminalIDFor!"ParametersAndQualifiers",
                        locationStr(declarator.location));
                assert(declarator.childs[1].childs[0].nonterminalID == nonterminalIDFor!"Parameters",
                        locationStr(declarator.location));
                assert(!declarator.childs[1].childs[0].childs[1].isValid
                        || declarator.childs[1].childs[0].childs[1].nonterminalID
                        == nonterminalIDFor!"ParameterDeclarationClause");
                skipToken(codeBefore, data, declarator.childs[1].childs[0].childs[0]); // (

                FunctionDeclaratorInfo functionDeclaratorInfo;
                findParams(declarator, condition, functionDeclaratorInfo, data, currentScope);

                bool needsComma = false; // !isFunctionDecl || r.length;
                foreach (i; 0 .. functionDeclaratorInfo.params.length)
                {
                    writeParam(codeMiddle, functionDeclaratorInfo.params[i], needsComma,
                            condition, data, currentScope, isStructConstructor && i == 0);
                }
                if (functionDeclaratorInfo.isVariadic)
                {
                    if (declarator.childs[1].childs[0].childs[1].childs.length >= 2)
                    {
                        if (declarator.childs[1].childs[0].childs[1].isValid
                                && declarator.childs[1].childs[0].childs[1].childs[$ - 2].isValid
                                && declarator.childs[1].childs[0].childs[1].childs[$ - 2].content == ",")
                            skipToken(codeMiddle, data,
                                    declarator.childs[1].childs[0].childs[1].childs[$ - 2]);
                        codeMiddle.write(",");
                    }
                    if (declarator.childs[1].childs[0].childs[1].isValid
                            && declarator.childs[1].childs[0].childs[1].childs[$ - 1].isValid
                            && declarator.childs[1].childs[0].childs[1].childs[$ - 1].content == "...")
                        skipToken(codeMiddle, data, declarator.childs[1].childs[0].childs[1].childs[$ - 1]);
                    codeMiddle.write("...");
                }
                skipToken(codeMiddle, data, declarator.childs[1].childs[0].childs[2]); // )

                if (functionDeclaratorInfo.attributeTrees.length)
                {
                    bool inComment;
                    foreach (t; functionDeclaratorInfo.attributeTrees)
                    {
                        bool needComment = true;
                        if (t.nameOrContent == "CvQualifier" && t.childs[0].nameOrContent == "const")
                            needComment = false;
                        else if (t.nonterminalID == nonterminalIDFor!"NoexceptSpecification"
                                && t.childs.length > 1)
                        {
                            continue;
                        }
                        else if (t.nameOrContent == "VirtSpecifier"
                                && t.childs[0].nameOrContent.among("override", "final"))
                        {
                            skipToken(codeAfter, data, t.childs[0], false, true);
                            continue;
                        }

                        if (needComment && !inComment)
                        {
                            codeAfter.write("/+");
                            inComment = true;
                        }
                        else if (!needComment && inComment)
                        {
                            codeAfter.write("+/");
                            inComment = false;
                        }
                        parseTreeToDCode(codeAfter, data, t, condition, currentScope);
                    }
                    if (inComment)
                    {
                        codeAfter.write("+/");
                    }
                }
            }
        }
        else
        {
            if (declarator.hasChildWithName("innerDeclarator"))
            {
                Tree c = declarator.childByName("innerDeclarator");
                if (c.isValid)
                {
                    writeComments(codeBefore, data,
                            data.sourceTokenManager.collectTokens(c.start));
                    visitDeclarator(c);
                }
            }
        }
        declaratorData.codeBefore = codeBefore.data.idup;
        declaratorData.codeMiddle = codeMiddle.data.idup;
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(codeAfter, data, data.sourceTokenManager.collectTokens(declarator.end));
        declaratorData.codeAfter = codeAfter.data.idup;
        r ~= declaratorData;
    }

    visitDeclarator(declarator);

    return r;
}

enum TypeToCodeFlags
{
    none,
    insideSkippedPointer = 1
}

string translateBuiltin(string name, bool builtinCppTypes)
{
    switch (name)
    {
    case "char":
        return "char";
    case "wchar":
        return "wchar_t";
    case "signed_char":
        return "byte";
    case "unsigned_char":
        return "ubyte";
    case "int":
        return "int";
    case "unsigned":
        return "uint";
    case "long":
        return builtinCppTypes ? "cpp_long" : "long";
    case "unsigned_long":
        return builtinCppTypes ? "cpp_ulong" : "ulong";
    case "long_long":
        return builtinCppTypes ? "cpp_longlong" : "long";
    case "unsigned_long_long":
        return builtinCppTypes ? "cpp_ulonglong" : "ulong";
    case "short":
        return "short";
    case "unsigned_short":
        return "ushort";
    case "_Bool":
        return "bool";
    case "va_list":
        return "cppconvhelpers.va_list";
    case "long_double":
        return "real";
    case "char8":
        return "char";
    case "char16":
        return "wchar";
    case "char32":
        return "dchar";
    case "int8":
        return "byte";
    case "int16":
        return "short";
    case "int32":
        return "int";
    case "int64":
        return "long";
    case "unsigned_int8":
        return "ubyte";
    case "unsigned_int16":
        return "ushort";
    case "unsigned_int32":
        return "uint";
    case "unsigned_int64":
        return "ulong";
    default:
        return name;
    }
}

void translateBuiltinAll(ref ConditionMap!string codeType, ref ConditionMap!string realId, immutable(Formula)* condition, bool isConst, DWriterData data)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    foreach (e; codeType.entries)
    {
        if (!logicSystem.and(e.condition, condition).isFalse)
        {
            string name = e.data;
            if (name.startsWith("$builtin_"))
            {
                name = translateBuiltin(normalizeBuiltinTypeParts(name[9 .. $].split("$builtin_")), data.options.builtinCppTypes);
            }
            if (isConst && name == "auto")
                name = ""; // const is enough
            realId.addReplace(e.condition, name, semantic.logicSystem);
        }
    }
}

string idMapToCode(ref ConditionMap!string realId, immutable(Formula)* condition, DWriterData data)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    string r;
    if (realId.entries.length == 1)
        r ~= realId.entries[0].data;
    else
    {
        r ~= "Identity!(mixin(";
        foreach (i, e; realId.entries)
        {
            if (i + 1 < realId.entries.length)
            {
                r ~= "(";
                auto simplified = logicSystem.removeRedundant(e.condition, condition);
                simplified = removeLocationInstanceConditions(simplified,
                        logicSystem, data.mergedFileByName);
                r ~= conditionToDCode(simplified, data);
                r ~= ")?";
            }
            r ~= "q{";
            r ~= e.data;
            r ~= "}";
            if (i + 1 < realId.entries.length)
                r ~= ":";
        }
        r ~= "))";
    }
    return r;
}

string typeToCode(QualType type, DWriterData data, immutable(Formula)* condition, Scope currentScope,
        LocationRangeX currentLoc, DeclaratorData[] declList,
        ref ConditionMap!string codeType, TypeToCodeFlags flags = TypeToCodeFlags.none)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    if (type.type is null)
    {
        CodeWriter code;
        code.write("UnknownType!q{");
        ConditionMap!string realId;
        translateBuiltinAll(codeType, realId, condition, false, data);
        if (realId.entries.length)
            code.write(idMapToCode(realId, condition, data));

        string codeBeforeDeclarator;
        string suffix;
        while (declList.length)
        {
            codeBeforeDeclarator ~= declList[0].codeBefore;
            suffix = declList[0].codeAfter ~ suffix;
            declList = declList[1 .. $];
        }

        code.write(codeBeforeDeclarator);
        code.write(suffix);
        code.write("}");
        return code.data.idup;
    }

    string r;

    string suffix;
    if (type.qualifiers & Qualifiers.const_)
    {
        if (type.kind == TypeKind.builtin && type.name == "auto")
        {
            r ~= "const";
        }
        else
        {
            r ~= "const(";
            suffix = ")";
        }
    }

    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        if (ctype.types.length == 1)
            return typeToCode(QualType(ctype.types[0].type,
                    ctype.types[0].qualifiers | type.qualifiers), data,
                    semantic.logicSystem.and(condition, ctype.conditions[0]),
                    currentScope, currentLoc, declList, codeType, TypeToCodeFlags.none);

        ConditionMap!string typeCode;

        foreach (i; 0 .. ctype.types.length)
        {
            if (semantic.logicSystem.and(condition, ctype.conditions[i]).isFalse)
                continue;
            typeCode.add(semantic.logicSystem.and(condition,
                    ctype.conditions[i]), typeToCode(QualType(ctype.types[i].type,
                    ctype.types[i].qualifiers | type.qualifiers), data,
                    semantic.logicSystem.and(condition, ctype.conditions[i]),
                    currentScope, currentLoc, declList, codeType, TypeToCodeFlags.none),
                    semantic.logicSystem);
        }

        typeCode.removeFalseEntries();

        r ~= idMapToCode(typeCode, condition, data);
        r ~= suffix;
        return r;
    }

    string codeBeforeDeclarator;
    while (declList.length && ((declList[0].tree.nonterminalID == nonterminalIDFor!"NoptrDeclarator"
            && declList[0].tree.childs.length == 4)
            || declList[0].tree.nonterminalID == nonterminalIDFor!"NoptrAbstractDeclarator"
            || declList[0].tree.nonterminalID == nonterminalIDFor!"AbstractDeclarator"))
    {
        codeBeforeDeclarator ~= declList[0].codeBefore;
        suffix = declList[0].codeAfter ~ suffix;
        declList = declList[1 .. $];
    }

    if (type.kind == TypeKind.pointer)
    {
        auto pointerType = cast(PointerType) type.type;

        Tree declarator;
        DeclaratorData[] nextDeclList;
        if (declList.length)
        {
            assert(declList[0].tree.nonterminalID.nonterminalIDAmong!("PtrDeclarator",
                    "PtrAbstractDeclarator", "ArrayDeclarator", "ArrayAbstractDeclarator"));
            declarator = declList[0].tree;
            if (declList[0].tree.nonterminalID.nonterminalIDAmong!("ArrayDeclarator",
                    "ArrayAbstractDeclarator"))
                codeBeforeDeclarator ~= "/+" ~ declList[0].codeBefore ~ "+/";
            else
                codeBeforeDeclarator ~= declList[0].codeBefore;
            suffix = declList[0].codeAfter ~ suffix;
            nextDeclList = declList[1 .. $];
        }
        else
            codeType = ConditionMap!string.init;

        ConditionMap!string typeCode;
        typeCode.conditionAll = semantic.logicSystem.false_;

        immutable(Formula)* isFunc = typeKindIs(pointerType.next.type,
                TypeKind.function_, semantic.logicSystem);
        if (!isFunc.isFalse)
        {
            typeCode.add(isFunc, typeToCode(pointerType.next, data,
                    semantic.logicSystem.and(isFunc, condition), currentScope, currentLoc, nextDeclList,
                    codeType, TypeToCodeFlags.insideSkippedPointer) ~ codeBeforeDeclarator,
                    semantic.logicSystem);
        }
        immutable(Formula)* isClass = typeIsClass(pointerType.next, data);
        if (!isClass.isFalse)
        {
            typeCode.add(isClass, typeToCode(pointerType.next, data,
                    semantic.logicSystem.and(isClass, condition), currentScope, currentLoc, nextDeclList,
                    codeType, TypeToCodeFlags.insideSkippedPointer) ~ codeBeforeDeclarator,
                    semantic.logicSystem);
        }
        immutable(Formula)* isOther = semantic.logicSystem.and(condition,
                typeCode.conditionAll.negated);
        typeCode.add(isOther, typeToCode(pointerType.next, data,
                semantic.logicSystem.and(isOther, condition), currentScope,
                currentLoc, nextDeclList, codeType, TypeToCodeFlags.none) ~ codeBeforeDeclarator ~ "*",
                semantic.logicSystem);

        typeCode.removeFalseEntries();

        r ~= idMapToCode(typeCode, condition, data);
        r ~= suffix;
        return r;
    }
    if (type.kind == TypeKind.reference)
    {
        auto pointerType = cast(ReferenceType) type.type;

        Tree declarator;
        DeclaratorData[] nextDeclList;
        if (declList.length)
        {
            assert(declList[0].tree.nonterminalID.nonterminalIDAmong!("PtrDeclarator",
                    "PtrAbstractDeclarator"));
            declarator = declList[0].tree;
            codeBeforeDeclarator ~= declList[0].codeBefore;
            suffix = declList[0].codeAfter ~ suffix;
            nextDeclList = declList[1 .. $];
        }

        string innerCode = "ref " ~ typeToCode(pointerType.next, data, condition, currentScope,
                currentLoc, nextDeclList, codeType, TypeToCodeFlags.none);

        return r ~ innerCode ~ codeBeforeDeclarator ~ suffix;
    }
    if (type.kind == TypeKind.rValueReference)
    {
        auto pointerType = cast(RValueReferenceType) type.type;

        Tree declarator;
        DeclaratorData[] nextDeclList;
        if (declList.length)
        {
            assert(declList[0].tree.nonterminalID.nonterminalIDAmong!("PtrDeclarator",
                    "PtrAbstractDeclarator"));
            declarator = declList[0].tree;
            codeBeforeDeclarator ~= declList[0].codeBefore;
            suffix = declList[0].codeAfter ~ suffix;
            nextDeclList = declList[1 .. $];
        }

        string innerCode = typeToCode(pointerType.next, data, condition,
                currentScope, currentLoc, nextDeclList, codeType, TypeToCodeFlags.none) ~ " && ";

        return r ~ innerCode ~ codeBeforeDeclarator ~ suffix;
    }
    if (type.kind == TypeKind.array)
    {
        ArrayType arrayType = cast(ArrayType) type.type;

        Tree declarator;
        DeclaratorData[] nextDeclList;
        if (declList.length)
        {
            assert(declList[0].tree.nonterminalID.nonterminalIDAmong!("ArrayDeclarator",
                    "ArrayAbstractDeclarator"));
            declarator = declList[0].tree;
            codeBeforeDeclarator ~= declList[0].codeBefore;
            suffix = declList[0].codeAfter ~ suffix;
            nextDeclList = declList[1 .. $];
        }

        string innerCode = typeToCode(arrayType.next, data, condition,
                currentScope, currentLoc, nextDeclList, codeType, TypeToCodeFlags.none);

        if (declarator.isValid)
            assert(declarator is arrayType.declarator);

        CodeWriter code;
        code.indentStr = data.options.indent;
        if (!declarator.isValid)
        {
            auto tokensLeftBak = data.sourceTokenManager.tokensLeft;
            data.sourceTokenManager.tokensLeft = typeof(data.sourceTokenManager.tokensLeft)();
            data.afterStringLiteral = false;
            code.write("[");
            if (!arrayType.declarator.isValid)
                code.write("0/* TODO: string literal has no declrarator for size. */");
            else
                parseTreeToDCode(code, data, arrayType.declarator.childs[2],
                        condition, currentScope);
            code.write("]");
            data.sourceTokenManager.tokensLeft = tokensLeftBak;
            if (code.data.length == 0)
                code.write("0");
        }
        return r ~ innerCode ~ codeBeforeDeclarator ~ code.data.idup ~ suffix;
    }
    if (type.kind == TypeKind.function_)
    {
        auto ftype = cast(FunctionType) type.type;

        Tree declarator;
        DeclaratorData[] nextDeclList;
        string codeMiddle;
        if (declList.length)
        {
            assert(declList[0].tree.nonterminalID.nonterminalIDAmong!("FunctionDeclarator",
                    "FunctionAbstractDeclarator"));
            declarator = declList[0].tree;
            codeBeforeDeclarator ~= declList[0].codeBefore;
            codeMiddle ~= declList[0].codeMiddle;
            suffix = declList[0].codeAfter ~ suffix;
            nextDeclList = declList[1 .. $];
        }

        CodeWriter code;
        code.indentStr = data.options.indent;
        auto mangling = getDefaultMangling(data, data.currentFilename);
        if (mangling == "C++")
            code.write("ExternCPPFunc!(");
        else if (mangling == "C")
            code.write("ExternCFunc!(");
        code.write(typeToCode(ftype.resultType, data, condition, currentScope,
                currentLoc, nextDeclList, codeType, TypeToCodeFlags.none));
        code.write(" function(");
        code.write(codeBeforeDeclarator);
        code.write(codeMiddle);
        if (!declarator.isValid)
        {
            foreach (i, t; ftype.parameters)
            {
                if (i)
                    code.write(", ");
                ConditionMap!string codeTypeDummy;
                code.write(typeToCode(t, data, condition, currentScope,
                        currentLoc, [], codeTypeDummy, TypeToCodeFlags.none));
            }
        }
        code.write(")");
        if (ftype.isConst)
            code.write(" const");
        if (mangling.among("C++", "C"))
            code.write(")");
        code.write(suffix);
        return code.data.idup;
    }
    assert(declList.length == 0, locationStr(declList[0].tree.location));
    if (type.kind == TypeKind.builtin)
    {
        string translation = translateBuiltin(type.name, data.options.builtinCppTypes);
        ConditionMap!string realId;
        bool isConst = (type.qualifiers & Qualifiers.const_) != 0;
        if (isConst && type.name == "auto")
            realId.add(condition, "", semantic.logicSystem); // const is enough
        else if (translation.length)
            realId.add(condition, translation, semantic.logicSystem);
        else
            realId.add(condition, type.name, semantic.logicSystem);
        translateBuiltinAll(codeType, realId, condition, isConst, data);
        realId.removeFalseEntries();

        if (realId.entries.length == 0)
            r ~= translation.length ? translation : type.name;
        else
            r ~= idMapToCode(realId, condition, data);
    }
    else if (type.kind.among(TypeKind.record, TypeKind.typedef_))
    {
        RecordType recordType = cast(RecordType) type.type;

        ConditionMap!Declaration realDecl;
        findRealDecl(recordType.declarationSet, type.kind == TypeKind.typedef_,
                realDecl, currentLoc, condition, data, currentScope);

        ConditionMap!string realId;
        foreach (e; codeType.entries)
        {
            if (!semantic.logicSystem.and(e.condition, condition).isFalse)
                realId.add(e.condition, e.data, semantic.logicSystem);
        }

        string templateArgs;
        if (recordType.next.length)
        {
            templateArgs ~= "!(";
            foreach (i, t2; recordType.next)
            {
                if (i)
                    templateArgs ~= ", ";
                ConditionMap!string codeTypeDummy;
                templateArgs ~= typeToCode(t2, data, condition, currentScope,
                        currentLoc, [], codeTypeDummy, TypeToCodeFlags.none);
            }
            templateArgs ~= ")";
        }
        foreach (e; realDecl.entries)
        {
            immutable(Formula)* newCondition = semantic.logicSystem.and(e.data.condition,
                    condition);
            if (realId.conditionAll !is null && (flags & TypeToCodeFlags.insideSkippedPointer) == 0)
                newCondition = semantic.logicSystem.and(newCondition, realId.conditionAll.negated);
            Declaration d = e.data;
            if (type.kind == TypeKind.typedef_ && isSelfTypedef(d, data))
            {
                d = getSelfTypedefTarget(d, data);
            }
            if (d in data.forwardDecls)
                newCondition = logicSystem.and(newCondition, data.forwardDecls[d].negated);
            string name = declarationNameToCode(d, data, currentScope, newCondition);
            if (d !in data.fileByDecl && realId.conditionAll !is null)
                newCondition = logicSystem.and(newCondition, realId.conditionAll.negated);

            name ~= templateArgs;

            if (d.type != DeclarationType.builtin && isClass(d.tree, data)
                    && (flags & TypeToCodeFlags.insideSkippedPointer) == 0)
            {
                name = "ValueClass!(" ~ name ~ ")";
            }

            realId.addReplace(newCondition, name, logicSystem);
        }
        realId.removeFalseEntries();

        if (realId.entries.length == 0)
            r ~= type.name ~ templateArgs;
        else
            r ~= idMapToCode(realId, condition, data);
    }
    else
        r ~= type.name;
    r ~= codeBeforeDeclarator;
    r ~= suffix;
    return r;
}
