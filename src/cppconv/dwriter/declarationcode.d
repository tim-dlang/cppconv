
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter.declarationcode;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.dwriter.dwriter;
import cppconv.dwriter.macrodeclaration;
import cppconv.dwriter.typecode;
import cppconv.dwriter.treecode;
import cppconv.dwriter.conditioncode;
import cppconv.grammarcpp;
import cppconv.preproc;
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

alias parseTreeToCodeTerminal = cppconv.dwriter.treecode.parseTreeToCodeTerminal;

Declaration getTypedefForDecl(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    if (!d.tree.isValid)
        return null;
    auto p1 = getRealParent(d.tree, semantic);
    if (!p1.isValid || !p1.nonterminalID.nonterminalIDAmong!("DeclSpecifierSeq"))
        return null;
    auto p2 = getRealParent(p1, semantic);
    if (!p2.isValid || p2.name != "SimpleDeclaration1")
        return null;
    foreach (d2; semantic.extraInfo(p2).declarations)
    {
        if ((d2.flags & DeclarationFlags.typedef_) == 0)
            continue;
        if (d2.condition !is d.condition)
            continue;
        QualType type2 = filterType(d2.type2, d.condition, semantic);
        if (type2.kind != TypeKind.record)
            continue;
        auto recordType = cast(RecordType) type2.type;
        if (recordType.declarationSet !is d.declarationSet)
            continue;
        return d2;
    }
    return null;
}

Declaration getSameRecordForTypedef(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    if (d.type2.type is null)
        return null;
    QualType type2 = filterType(d.type2, d.condition, semantic);
    if (type2.kind != TypeKind.record)
        return null;
    if (type2.name == "")
        return null;
    string replacedName = replaceTypeName(data, d, semantic);
    auto recordType = cast(RecordType) type2.type;
    foreach (e; recordType.declarationSet.entries)
    {
        auto d2 = e.data;
        if ((d2.flags & DeclarationFlags.typedef_) != 0)
            continue;
        if (e.condition !is d.condition)
            continue;
        if (replacedName != replaceTypeName(data, d2, semantic))
            continue;
        if (d2.realDeclaration.entries.length)
        {
            if (d2.realDeclaration.entries.length != 1)
                continue;
            if (d2.realDeclaration.entries[0].condition !is d.condition)
                continue;
            d2 = d2.realDeclaration.entries[0].data;
        }
        return d2;
    }
    return null;
}

Declaration getSelfTypedefTarget(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    auto sameRecord = getSameRecordForTypedef(d, data);
    if (sameRecord !is null)
        return sameRecord;

    if (d.type2.type is null)
        return null;
    QualType type2 = filterType(d.type2, d.condition, semantic);
    if (type2.kind == TypeKind.record)
    {
        if (type2.name != "")
            return null;
        auto recordType = cast(RecordType) type2.type;
        foreach (e; recordType.declarationSet.entries)
        {
            if ((e.data.flags & DeclarationFlags.typedef_) != 0)
                continue;
            if (e.condition !is d.condition)
                continue;

            if (getTypedefForDecl(e.data, data) is d)
                return e.data;
        }
    }
    if (type2.kind == TypeKind.builtin)
    {
        ConditionMap!string codeType;
        string name2 = typeToCode(type2, data, d.condition, semantic.rootScope,
                LocationRangeX.init, [], codeType);
        if (d.name == type2.name || d.name == name2)
        {
            auto r = new Declaration;
            r.name = d.name;
            r.condition = d.condition;
            r.type = DeclarationType.builtin;
            return r;
        }
    }
    return null;
}

bool isSelfTypedef(Declaration d, DWriterData data)
{
    Declaration target = getSelfTypedefTarget(d, data);
    if (target !is null)
        return true;
    return false;
}

string chooseDeclarationName(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    if (d.name == "" && d.type != DeclarationType.type)
        return "";

    if (d.type == DeclarationType.varOrFunc && d.scope_.tree.isValid
            && d.scope_.tree.nonterminalID == nonterminalIDFor!"ClassSpecifier")
        return replaceKeywords(d.name);

    auto declarationData = data.declarationData(d);
    if (d.type == DeclarationType.varOrFunc && (d.flags & DeclarationFlags.function_) != 0)
    {
        if (auto inChosenName = d.declarationSet in data.functionChosenName)
            return *inChosenName;
    }
    else
    {
        if (declarationData.chosenName.length)
            return declarationData.chosenName;
    }

    immutable(Formula)* skipForward = semantic.logicSystem.false_;
    if (auto inForwardDecls = d in data.forwardDecls)
        skipForward = *inForwardDecls;
    immutable(Formula)* condition2 = semantic.logicSystem.and(d.condition, skipForward.negated);
    if (d.realDeclaration.conditionAll !is null)
        condition2 = semantic.logicSystem.and(condition2, d.realDeclaration.conditionAll.negated);
    if (condition2.isFalse)
        return d.name;

    if (d.type == DeclarationType.varOrFunc && (d.flags & DeclarationFlags.function_) != 0)
    {
        string name = d.name;
        name = replaceKeywords(name);

        name = getFreeName(name, getDeclarationFilename(d, data), condition2, data, d.scope_);
        data.functionChosenName[d.declarationSet] = name;
        return name;
    }

    if (d.flags & DeclarationFlags.templateSpecialization)
    {
        foreach (e; d.declarationSet.entries)
        {
            if (e.data.type != d.type)
                continue;
            if (e.data.flags & DeclarationFlags.templateSpecialization)
                continue;
            if (e.data.flags & DeclarationFlags.forward)
                continue;
            declarationData.chosenName = chooseDeclarationName(e.data, data);
            return declarationData.chosenName;
        }
    }
    if (d.name.length == 0 && d.type == DeclarationType.type
            && (d.flags & DeclarationFlags.typedef_) == 0)
    {
        auto d2 = getTypedefForDecl(d, data);
        if (d2 !is null)
        {
            declarationData.chosenName = chooseDeclarationName(d2, data);
            return declarationData.chosenName;
        }
    }
    if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0)
    {
        auto d2 = getSameRecordForTypedef(d, data);
        if (d2 !is null)
        {
            declarationData.chosenName = chooseDeclarationName(d2, data);
            return declarationData.chosenName;
        }
    }

    string name = d.name;

    if (d.type == DeclarationType.type)
        name = replaceTypeName(data, d, semantic);

    if (name.length == 0 && d.tree.isValid
            && (d.tree.nonterminalID == nonterminalIDFor!"EnumSpecifier"
                || (d.declarationSet.scope_ !is semantic.rootScope
                && d.tree.nameOrContent == "ClassSpecifier"
                && d.tree.childs[0].nameOrContent == "ClassHead"
                && d.tree.childs[0].childs[0].nameOrContent == "ClassKey"
                && d.tree.childs[0].childs[0].childs[0].nameOrContent == "union")))
    {
        auto parent = getRealParent(d.tree, semantic);
        auto parent2 = getRealParent(parent, semantic);
        if (!parent2.isValid)
            return "";
        bool anyUsingDecl;
        foreach (d2; semantic.extraInfo(parent2).declarations)
            if (d2.type != DeclarationType.type)
                anyUsingDecl = true;
        if (!anyUsingDecl)
            return "";
    }

    if (name.length == 0)
    {
        name = "generated_";
        auto locContext = d.tree.start.context;
        if (locContext.name == "^")
            locContext = locContext.prev;
        string filename = locContext.filename;
        foreach_reverse (i, char c; filename)
        {
            if (c == '/')
            {
                filename = filename[i + 1 .. $];
                break;
            }
        }
        foreach (i, char c; filename)
        {
            if (c.inCharSet!"a-zA-Z0-9")
                name ~= c;
            else if (c == '.')
            {
                break;
            }
        }
        name ~= "_";
        if (locContext.name.length)
            name ~= locContext.name ~ "_";
        if (name !in semantic.generatedNameCounters)
            semantic.generatedNameCounters[name] = 0;
        else
            semantic.generatedNameCounters[name]++;
        name ~= text(semantic.generatedNameCounters[name]);
    }

    name = replaceKeywords(name);

    declarationData.chosenName = getFreeName(name, getDeclarationFilename(d, data), condition2, data, d.scope_);
    return declarationData.chosenName;
}

struct ParamData
{
    Declaration declaration;
    Declaration realDeclaration;
    immutable(Formula)* condition;
    Tree[] commaTokens;
}

struct FunctionDeclaratorInfo
{
    ParamData[] params;
    bool isVariadic;
    Tree[] attributeTrees;
    Tree functionDeclarator;
    Tree[] commaTokens;
}

void findParams(Tree t, immutable(Formula)* condition3,
        ref FunctionDeclaratorInfo info, DWriterData data, Scope currentScope)
{
    auto semantic = data.semantic;
    if (!t.isValid)
        return;
    if (t.nodeType == NodeType.array)
    {
        foreach (c; t.childs)
            findParams(c, condition3, info, data, currentScope);
    }
    else if (t.nodeType == NodeType.token)
    {
        if (t.content == ",")
            info.commaTokens ~= t;
        if (t.content == "...")
            info.isVariadic = true;
    }
    else if (t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = t.toConditionTree;
        foreach (i; 0 .. ctree.conditions.length)
        {
            auto condition4 = semantic.logicSystem.and(condition3, ctree.conditions[i]);
            if (!condition4.isFalse)
                findParams(ctree.childs[i], condition4, info, data, currentScope);
        }
    }
    else if (t.nodeType == NodeType.merged)
    {
        auto mdata = semantic.mergedTreeData(t);
        foreach (i; 0 .. mdata.conditions.length)
        {
            auto condition4 = semantic.logicSystem.and(condition3, mdata.conditions[i]);
            if (!condition4.isFalse)
                findParams(t.childs[i], condition4, info, data, currentScope);
        }
    }
    else if (t.nonterminalID.nonterminalIDAmong!("FunctionDeclarator",
            "FunctionDeclaratorTrailing", "FunctionAbstractDeclarator"))
    {
        info.functionDeclarator = t;
        findParams(t.childs[1], condition3, info, data, currentScope);
        findParams(t.childByName("virtSpec"), condition3, info, data, currentScope);
        //parseTreeToDCode(code, data, t.childs[1], condition2, currentScope);
    }
    else if (t.nonterminalID.nonterminalIDAmong!("LambdaDeclarator"))
    {
        info.functionDeclarator = t;
        findParams(t.childs[1], condition3, info, data, currentScope);
    }
    else if (t.nonterminalID.nonterminalIDAmong!("ParameterDeclaration",
            "ParameterDeclarationAbstract"))
    {
        foreach (d; semantic.extraInfo(t).declarations)
        {
            if (d.type == DeclarationType.type)
                continue;
            auto condition4 = d.condition;
            if (condition4 is null)
                condition4 = semantic.logicSystem.true_;
            condition4 = semantic.logicSystem.and(condition4, condition3);
            immutable(Formula)* conditionLeft = condition4;
            foreach (e; d.realDeclaration.entries)
            {
                auto condition5 = semantic.logicSystem.and(condition4, e.condition);
                if (condition5.isFalse)
                    continue;
                ParamData p;
                p.condition = condition4;
                p.realDeclaration = e.data;
                p.declaration = d;
                p.commaTokens = info.commaTokens;
                info.commaTokens = [];
                info.params ~= p;
                conditionLeft = semantic.logicSystem.and(conditionLeft, condition5.negated);
            }

            if (!conditionLeft.isFalse)
            {
                ParamData p;
                p.condition = conditionLeft;
                p.realDeclaration = d;
                p.declaration = d;
                p.commaTokens = info.commaTokens;
                info.commaTokens = [];
                info.params ~= p;
            }
        }
    }
    else if (t.nonterminalID.nonterminalIDAmong!("ParametersAndQualifiers", "LambdaParametersAndQualifiers"))
    {
        if (auto childScope = (currentScope !is null) ? t in currentScope.childScopeByTree : null)
            currentScope = *childScope;

        findParams(t.childs[0], condition3, info, data, currentScope);

        Tree qualifiersSeq = t.childByName("qualifiersSeq");
        if (qualifiersSeq.isValid)
        {
            if (qualifiersSeq.nodeType == NodeType.array)
                info.attributeTrees ~= qualifiersSeq.childs;
            else
                info.attributeTrees ~= qualifiersSeq;
        }
    }
    else if (t.nonterminalID == nonterminalIDFor!"Parameters")
    {
        findParams(t.childs[1], condition3, info, data, currentScope);
    }
    else if (t.nonterminalID == nonterminalIDFor!"VirtSpecifier")
    {
        info.attributeTrees ~= t;
    }
    else if (t.nodeType == NodeType.nonterminal && t.hasChildWithName("innerDeclarator"))
        findParams(t.childByName("innerDeclarator"), condition3, info, data, currentScope);
}

void writeParam(ref CodeWriter code, ref ParamData p, ref bool needsComma,
        immutable(Formula)* condition2, DWriterData data, Scope currentScope, bool skipInitializer = false)
{
    auto semantic = data.semantic;
    auto condition4 = p.condition;
    auto d2 = p.declaration;

    foreach (t; p.commaTokens)
        skipToken(code, data, t);

    if (needsComma)
        parseTreeToCodeTerminal(code, ",");

    Tree declSeq = d2.tree.childs[0];

    ConditionMap!string codeType;
    CodeWriter codeAfterDeclSeq;
    codeAfterDeclSeq.indentStr = data.options.indent;
    bool afterTypeInDeclSeq;
    if (declSeq.isValid /* && data.sourceTokenManager.tokensLeft.data.length > 0*/ )
    {
        collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                afterTypeInDeclSeq, declSeq.childs[0], condition4, data, currentScope);
        if (d2.tree.childs[1].isValid)
            writeComments(codeAfterDeclSeq, data, d2.tree.childs[1].start);
    }

    Tree realDeclarator = d2.declaratorTree;
    if (realDeclarator.isValid && realDeclarator.nonterminalID == nonterminalIDFor!"InitDeclarator")
        realDeclarator = realDeclarator.childs[0];
    if (realDeclarator.isValid
            && realDeclarator.nonterminalID == nonterminalIDFor!"MemberDeclarator")
        realDeclarator = realDeclarator.childs[0];

    string typeCode2 = typeToCode(d2.type2, data, condition4, currentScope, p.declaration.location,
            declaratorList(realDeclarator, d2.condition, data, currentScope), codeType);
    typeCode2 ~= codeAfterDeclSeq.data;
    if (typeCode2 == "void" && d2.name.length == 0)
        return;
    string name2 = chooseDeclarationName(p.realDeclaration, data);

    bool isReference;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, semantic.logicSystem.and(condition2, condition4), null, semantic.mergedTreeDatas);
        auto t = chooseType(d2.type2, ppVersion, true);
        if (t.kind == TypeKind.reference)
        {
            isReference = true;
        }
    }

    needsComma = true;
    if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
        code.write(" ");
    if (semantic.logicSystem.and(condition2, condition4.negated).isFalse)
    {
        code.write(typeCode2);
        if (name2.length)
        {
            if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                code.write(" ");
            code.write(name2);

            if (d2.tree.nonterminalID == nonterminalIDFor!"ParameterDeclaration"
                    && d2.tree.childs.length == 4 && !isReference)
            {
                if (skipInitializer)
                    code.write("/+");
                parseTreeToDCode(code, data, d2.tree.childs[2],
                        semantic.logicSystem.and(condition2, condition4), currentScope);
                parseTreeToDCode(code, data, d2.tree.childs[3],
                        semantic.logicSystem.and(condition2, condition4), currentScope);
                if (skipInitializer)
                    code.write("+/");
            }
            else if (auto match = d2.tree.matchTreePattern!q{
                    ParameterDeclaration(*, *, *, InitializerClause(e = PostfixExpression(c = *, "(", [], ")")))
                } & isReference)
            {
                parseTreeToDCode(code, data, d2.tree.childs[2],
                        semantic.logicSystem.and(condition2, condition4), currentScope);
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(code, data, match.savedc.start);
                code.write("globalInitVar!");
                bool needsParens = match.savedc.name != "NameIdentifier";
                if (needsParens)
                    code.write("(");
                parseTreeToDCode(code, data, match.savedc,
                        semantic.logicSystem.and(condition2, condition4), currentScope);
                skipToken(code, data, match.savede.childs[1]);
                skipToken(code, data, match.savede.childs[3]);
                if (needsParens)
                    code.write(")");
            }
        }
    }
    else
    {
        auto simplified2 = semantic.logicSystem.removeRedundant(condition4, condition2);
        simplified2 = removeLocationInstanceConditions(simplified2,
                semantic.logicSystem, data.mergedFileByName);
        code.write("mixin((", conditionToDCode(simplified2, data), ") ? q{",
                typeCode2, "} : q{AliasSeq!()})");
        if (name2.length)
        {
            if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                code.write(" ");
            code.write(name2);
        }
    }
}

Scope getContextScope(Tree tree, ref IteratePPVersions ppVersion,
        Semantic semantic, Scope currentScope)
{
    assert(tree.nonterminalID == nonterminalIDFor!"NameIdentifier");

    Scope contextScope = currentScope;

    size_t indexInParentX;
    Tree parentX = getRealParent(tree, semantic, &indexInParentX);

    if (parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"SimpleTemplateId"
            && indexInParentX == 0)
    {
        parentX = getRealParent(parentX, semantic, &indexInParentX);
    }

    if (parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"QualifiedId"
            && parentX.childs.length == 3 && indexInParentX == 2)
    {
        Tree nsTree = ppVersion.chooseTree(parentX.childs[0]);
        QualType nsType = chooseType(semantic.extraInfo(nsTree).type, ppVersion, true);
        if (nsType.kind.among(TypeKind.namespace, TypeKind.record))
            contextScope = scopeForRecord(nsType.type, ppVersion, semantic);
    }
    if (parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"TypenameSpecifier"
            && indexInParentX == parentX.childs.length - 1)
    {
        Tree nsTree = ppVersion.chooseTree(parentX.childs[1]);
        QualType nsType = chooseType(semantic.extraInfo(nsTree).type, ppVersion, true);
        if (nsType.kind.among(TypeKind.namespace, TypeKind.record))
            contextScope = scopeForRecord(nsType.type, ppVersion, semantic);
    }
    if (parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"SimpleTypeSpecifierNoKeyword"
            && indexInParentX == parentX.childs.length - 1)
    {
        Tree nsTree = ppVersion.chooseTree(parentX.childByName("nestedName"));
        QualType nsType = chooseType(semantic.extraInfo(nsTree).type, ppVersion, true);
        if (nsType.kind.among(TypeKind.namespace, TypeKind.record))
            contextScope = scopeForRecord(nsType.type, ppVersion, semantic);
    }
    if (parentX.isValid && parentX.nonterminalID == nonterminalIDFor!"NestedNameSpecifierHead"
            && indexInParentX == parentX.childs.length - 1)
    {
        Tree nsTree = ppVersion.chooseTree(parentX.childs[0]);
        QualType nsType = chooseType(semantic.extraInfo(nsTree).type, ppVersion, true);
        if (nsType.kind.among(TypeKind.namespace, TypeKind.record))
            contextScope = scopeForRecord(nsType.type, ppVersion, semantic);
    }
    return contextScope;
}

bool getLastLineIndent(ref CodeWriter code, ref string indent)
{
    code.startLine();
    indent = code.lastLineIndent.idup;
    if (code.indent * code.indentStr.length < indent.length)
        indent = indent[code.indent * code.indentStr.length .. $];
    return code.inLine && !code.inIndent;
}

void declarationToDCodeBefore(ref CodeWriter code, DWriterData data, Declaration d,
        immutable(Formula)* condition, Declaration forwardDecl = null, bool skipEmptyLines = false)
{
    auto semantic = data.semantic;
    auto declarationTokens = data.sourceTokenManager.declarationTokens(d);
    if (declarationTokens.tokensBefore.length == 0)
        return;

    auto tokens = declarationTokens.tokensBefore;
    if (skipEmptyLines)
    {
        bool anyNewline;
        while (tokens.length && tokens[0].token.content.among("\n", "\r\n"))
        {
            tokens = tokens[1 .. $];
            anyNewline = true;
        }
    }

    writeComments(code, data, tokens);
}

void declarationToDCode2(ref CodeWriter code, DWriterData data, Declaration d,
        immutable(Formula)* condition, Declaration forwardDecl = null)
{
    auto semantic = data.semantic;
    auto logicSystem = data.logicSystem;
    auto declarationTokens = data.sourceTokenManager.declarationTokens(d);

    if (forwardDecl is null)
        writeComments(code, data, declarationTokens.tokensBefore);

    immutable(Formula)* skipForward = logicSystem.false_;
    if (auto inForwardDecls = d in data.forwardDecls)
        skipForward = *inForwardDecls;

    string lastLineIndent;
    if (getLastLineIndent(code, lastLineIndent) && data.options.addDeclComments)
        code.writeln();
    string origCustomIndent = code.customIndent;
    string newCustomIndent = lastLineIndent.length ? lastLineIndent : code.customIndent;
    code.customIndent = newCustomIndent;
    scope (success)
        code.customIndent = origCustomIndent;

    bool closeComment;
    if (d.condition.isFalse)
    {
        code.writeln("/+");
        closeComment = true;
    }
    else if (semantic.logicSystem.and(d.condition, skipForward.negated).isFalse)
    {
        code.writeln("/+ skip forward");
        closeComment = true;
    }
    else if (!semantic.logicSystem.and(d.condition, skipForward).isFalse)
    {
        if (data.options.addDeclComments)
            code.writeln("// skip forward ", skipForward.toString);
    }

    if (forwardDecl is null && code.inLine && !code.inIndent)
        code.writeln();

    code.startLine();
    code.customIndent = origCustomIndent;

    assert(data.sourceTokenManager.tokensLeft.data.length == 0);
    LocationRangeX locRange = d.location;
    if (d.tree.isValid)
        locRange = d.tree.location;
    locRange = locRange.nonMacroLocation;
    if (true  /*d.type == DeclarationType.comment*/ )
    {
        foreach (i; 0 .. d.location.nonMacroLocation.context.contextDepth - 1)
            data.sourceTokenManager.tokensLeft.put(SourceToken[].init);
        data.sourceTokenManager.tokensLeft.put(declarationTokens.tokensInside);
        data.sourceTokenManager.locDone = locRange.start;
    }

    declarationToDCode(code, data, d, condition, closeComment ? null : skipForward, forwardDecl);

    if (data.sourceTokenManager.tokensLeft.data.length)
    {
        writeComments(code, data, locRange.end);
        auto tokens = data.sourceTokenManager.collectTokens(LocationX.init, true);
        if (forwardDecl !is null)
        {
            while (tokens.length && tokens[$ - 1].isWhitespace
                    && tokens[$ - 1].token.content.among("\n", "\r\n"))
                tokens = tokens[0 .. $ - 1];
        }
        writeComments(code, data, tokens);
    }

    SourceToken[] tokensAfter = declarationTokens.tokensAfter;
    foreach (i, t; tokensAfter)
        if (t.token.content == ";")
        {
            writeComments(code, data, tokensAfter[0 .. i]);
            tokensAfter = tokensAfter[i + 1 .. $];
            break;
        }
    writeComments(code, data, tokensAfter);

    data.sourceTokenManager.tokensLeft.shrinkTo(0);

    code.customIndent = newCustomIndent;

    if (closeComment)
    {
        if (code.inLine)
            code.writeln();
        code.writeln("+/");
    }
}

struct CodeTokenInfoBak
{
    LocationX locDoneBak;
    SourceToken[][] tokensLeftBak;
    immutable(LocationContext)* tokensContextBak;
    bool inInterpolateMixinBak;

    LocationRangeX outerDeclLoc;
    bool outerMoved;
}

CodeTokenInfoBak saveCodeTokenInfo(ref CodeWriter code, DWriterData data)
{
    CodeTokenInfoBak bak;
    bak.locDoneBak = data.sourceTokenManager.locDone;
    bak.tokensLeftBak = data.sourceTokenManager.tokensLeft.data.dup;
    bak.tokensContextBak = data.sourceTokenManager.tokensContext;
    bak.inInterpolateMixinBak = data.sourceTokenManager.inInterpolateMixin;
    data.sourceTokenManager.tokensLeft.shrinkTo(0);
    return bak;
}

void restoreCodeTokenInfoBak(ref CodeWriter code, DWriterData data, CodeTokenInfoBak bak)
{
    assert(data.sourceTokenManager.tokensLeft.data.length == 0);
    data.sourceTokenManager.locDone = bak.locDoneBak;
    data.sourceTokenManager.tokensLeft.put(bak.tokensLeftBak);
    data.sourceTokenManager.tokensContext = bak.tokensContextBak;
    data.sourceTokenManager.inInterpolateMixin = bak.inInterpolateMixinBak;
}

void declarationToDCode2Bak(ref CodeWriter code, DWriterData data, Declaration d,
        immutable(Formula)* condition, Declaration forwardDecl = null)
{
    auto bak = saveCodeTokenInfo(code, data);

    declarationToDCode2(code, data, d, condition, forwardDecl);

    restoreCodeTokenInfoBak(code, data, bak);
}

bool isSubCode(string a_, string b_)
{
    string a = a_;
    string b = b_;
    while (true)
    {
        while (a.length && a[0].inCharSet!" \t\n\r")
            a = a[1 .. $];
        while (b.length && b[0].inCharSet!" \t\n\r")
            b = b[1 .. $];
        if (a.length == 0)
            return true;
        if (b.length == 0)
            return false;
        if (a[0] == b[0])
        {
            a = a[1 .. $];
            b = b[1 .. $];
        }
        else
        {
            b = b[1 .. $];
        }
    }
}

void declarationToDCode(ref CodeWriter code, DWriterData data, Declaration d, immutable(Formula)* condition,
        immutable(Formula)* forwardCondition = null, Declaration forwardDecl = null)
{
    assert(d.type != DeclarationType.forwardScope);

    auto semantic = data.semantic;
    auto logicSystem = data.logicSystem;

    data.markDeclarationUsed(d);

    auto declarationData = data.declarationData(d);
    auto forwardDecl2 = forwardDecl !is null ? forwardDecl : d;

    string lastLineIndent;
    if (getLastLineIndent(code, lastLineIndent) && data.options.addDeclComments)
        code.writeln();
    string origCustomIndent = code.customIndent;
    string newCustomIndent = lastLineIndent.length ? lastLineIndent : code.customIndent;
    code.customIndent = newCustomIndent;
    scope (success)
        code.customIndent = origCustomIndent;

    if (d.type != DeclarationType.comment && data.options.addDeclComments)
        code.writeln("// ", d.name);

    Declaration lastDeclaration = data.currentDeclaration;
    data.currentDeclaration = d;
    scope (success)
        data.currentDeclaration = lastDeclaration;

    auto condition2 = d.condition;
    if (condition2 is null)
        condition2 = semantic.logicSystem.true_;
    condition2 = semantic.logicSystem.and(condition2, condition);
    if (forwardCondition !is null)
        condition2 = semantic.logicSystem.and(condition2, forwardCondition.negated);
    auto simplified = logicSystem.removeRedundant(removeLocationInstanceConditions(condition2,
            logicSystem, data.mergedFileByName),
            removeLocationInstanceConditions(condition, logicSystem, data.mergedFileByName));
    if (d.type != DeclarationType.comment && data.options.addDeclComments)
    {
        if (d.location.context !is null && data.sourceTokenManager.tokensContext is null)
        {
            //code.writeln("// contextCondition ", condition.toString);
            code.writeln("// ", d.condition is null ? "condition=null" : d.condition.toString);
        }
        code.writeln("// ", d.type);
        if (d.location.context !is null && data.sourceTokenManager.tokensContext is null)
        {
            auto loc = d.location.start;
            code.writeln("// ", locationStr(loc).replace("+/", "+ /"));
        }
    }

    Scope parentScope;
    if (forwardDecl !is null)
    {
        parentScope = forwardDecl.scope_;
        if (parentScope is null && forwardDecl.declarationSet !is null)
            parentScope = forwardDecl.declarationSet.scope_;
    }
    else
    {
        parentScope = d.scope_;
        if (parentScope is null && d.declarationSet !is null)
            parentScope = d.declarationSet.scope_;
    }
    Tree parentClassTree;
    if (parentScope !is null && parentScope.tree.isValid && parentScope.tree.name
            == "ClassSpecifier")
        parentClassTree = parentScope.tree;

    Scope currentScope = d.scope_;
    if (currentScope is null && d.declarationSet !is null)
        currentScope = d.declarationSet.scope_;
    if (d.tree.isValid && d.tree.nameOrContent == "ClassSpecifier"
            && d.tree in semantic.rootScope.childScopeByTree)
        currentScope = semantic.rootScope.childScopeByTree[d.tree];
    if (auto childScope = (currentScope !is null) ? d.tree in currentScope.childScopeByTree : null)
        currentScope = *childScope;

    bool closeStaticIf;
    if (!simplified.isTrue && !condition.isFalse)
    {
        if (!isVersionOnlyCondition(simplified, data))
        {
            string conditionCode = conditionToDCode(simplified, data);
            if (conditionCode.startsWith("("))
                code.writeln("static if ", conditionCode, "");
            else
                code.writeln("static if (", conditionCode, ")");
        }
        else
        {
            versionConditionToDCode(code, simplified, data);
        }
        code.writeln("{");
        closeStaticIf = true;
    }
    scope (success)
        if (closeStaticIf)
        {
            if (code.inLine)
                code.writeln();
            code.writeln("}");
        }

    if (d.scope_ !is null && (d.flags & DeclarationFlags.forward) == 0)
    {
        string fname = fullyQualifiedName(semantic, d);
        if (auto inDocComments = fname in data.options.docComments)
        {
            string lastLineIndentUnused;
            if (getLastLineIndent(code, lastLineIndentUnused))
                code.writeln();
            code.writeln("/// ", *inDocComments);
        }
    }

    Tree[] templateDeclarations = findParentTemplateDeclarations(d.tree, semantic);
    CodeWriter templateParamCodeWriter;
    foreach_reverse (t; templateDeclarations)
    {
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data, t.start);
        skipToken(templateParamCodeWriter, data, t.childs[0], false, true);
        skipToken(templateParamCodeWriter, data, t.childs[1], false, true);
        buildTemplateParamCode(t.childs[2], condition2, templateParamCodeWriter, data);
        writeComments(templateParamCodeWriter, data, t.childs[3].start);
        CodeWriter dummy;
        skipToken(dummy, data, t.childs[3], false, true);
    }
    data.declarationData(d).templateParamCode = templateParamCodeWriter.data.idup;
    if (templateDeclarations.length && data.sourceTokenManager.tokensLeft.data.length > 0)
    {
        auto tokens = data.sourceTokenManager.collectTokens(d.tree.start);
        if (tokens.length && tokens[0].isWhitespace && tokens[0].token.content == newCustomIndent)
            tokens = tokens[1 .. $];
        writeComments(code, data, tokens);
    }
    scope (success)
    {
        string templateParamCode = data.declarationData(d).templateParamCode;
        if (templateParamCode.length)
            code.writeln("\n/+TODO: missing template args: ", templateParamCode, "+/");
    }

    if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0)
    {
        ConditionMap!string codeType;
        CodeWriter codeAfterDeclSeq;
        codeAfterDeclSeq.indentStr = data.options.indent;
        bool afterTypeInDeclSeq;
        //if (data.sourceTokenManager.tokensLeft.data.length > 0)
        {
            if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration1",
                    "SimpleDeclaration3", "MemberDeclaration1",
                    "ParameterDeclaration", "Condition",
                    "ForRangeDeclaration", "ExceptionDeclaration"))
            {
                collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                        afterTypeInDeclSeq, d.tree.childs[0], condition2, data, currentScope);
                writeComments(codeAfterDeclSeq, data, d.tree.childs[1].start);
            }
            else if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration2"))
            {
            }
            else
                assert(false, d.tree.name);
        }
        Tree realDeclarator = d.declaratorTree;
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"InitDeclarator")
            realDeclarator = realDeclarator.childs[0];
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"MemberDeclarator")
            realDeclarator = realDeclarator.childs[0];

        string typeCode = typeToCode(d.type2, data, condition2, currentScope, d.location,
                declaratorList(realDeclarator, d.condition, data, currentScope), codeType);
        typeCode ~= codeAfterDeclSeq.data;
        while (typeCode.length && typeCode[$ - 1].inCharSet!" \t")
            typeCode = typeCode[0 .. $ - 1];
        string usedName = chooseDeclarationName(d, data);
        if (isSelfTypedef(d, data))
            code.write("// self alias: ");
        code.write("alias ", usedName, " = ", typeCode);
        if (d.tree.childs[$ - 1].content == ";")
            parseTreeToDCode(code, data, d.tree.childs[$ - 1], condition2, currentScope); // ;
        else
            code.writeln(";");
    }
    else if (d.type == DeclarationType.type
            && d.tree.nonterminalID == nonterminalIDFor!"AliasDeclaration")
    {
        string usedName = chooseDeclarationName(d, data);
        skipToken(code, data, d.tree.childs[0]);
        code.write("alias");
        skipToken(code, data, d.tree.childs[1]);
        code.write(usedName);
        if (templateParamCodeWriter.data.length)
        {
            code.write("(", templateParamCodeWriter.data, ")");
            data.declarationData(d).templateParamCode = "";
        }
        parseTreeToDCode(code, data, d.tree.childs[$ - 3], condition2, currentScope); // =
        parseTreeToDCode(code, data, d.tree.childs[$ - 2], condition2, currentScope);
        parseTreeToDCode(code, data, d.tree.childs[$ - 1], condition2, currentScope); // ;
    }
    else if ((d.type == DeclarationType.varOrFunc || d.type == DeclarationType.type) && d.tree.nonterminalID.nonterminalIDAmong!("UsingDeclaration"))
    {
        string usedName = chooseDeclarationName(d, data);
        skipToken(code, data, d.tree.childs[0]);
        code.write("alias ");
        code.write(usedName);
        code.write(" =");
        parseTreeToDCode(code, data, d.declaratorTree, condition2, currentScope);
        code.write(";");
    }
    else if (d.bitFieldInfo.entries.length)
    {
        if (data.sourceTokenManager.tokensLeft.data.length)
        {
            writeComments(code, data, d.tree.end);
        }
        ConditionMap!string codeType;
        string typeCode = typeToCode(d.type2, data, condition2, currentScope,
                d.location, [], codeType);
        foreach (e; d.bitFieldInfo.entries)
        {
            bool closeBraces;
            if (!semantic.logicSystem.and(e.condition.negated, condition2).isFalse)
            {
                code.writeln("static if (", conditionToDCode(e.condition, data), ")");
                code.writeln("{");
                closeBraces = true;
            }

            if (e.data.firstBit == 0)
            {
                if (e.data.wholeLength <= 8)
                    code.writeln("ubyte ", e.data.dataName, ";");
                else if (e.data.wholeLength <= 16)
                    code.writeln("ushort ", e.data.dataName, ";");
                else if (e.data.wholeLength <= 32)
                    code.writeln("uint ", e.data.dataName, ";");
                else if (e.data.wholeLength <= 64)
                    code.writeln("ulong ", e.data.dataName, ";");
                else
                    code.writeln("Unknownbitfield", e.data.wholeLength, " ",
                            e.data.dataName, "; // TODO");
            }

            if (d.name.length)
            {
                if (data.currentClassDeclaration !is null
                        && isClass(data.currentClassDeclaration.tree, data))
                    code.write("final ");
                code.writeln(typeCode, " ", replaceKeywords(d.name), "() const nothrow");
                code.writeln("{").incIndent;
                code.writeln("return (", e.data.dataName, " >> ",
                        e.data.firstBit, ") & ",
                        hexMaskCode(e.data.length, 0), ";");
                code.decIndent.writeln("}");
                if (data.currentClassDeclaration !is null
                        && isClass(data.currentClassDeclaration.tree, data))
                    code.write("final ");
                code.writeln(typeCode, " ", replaceKeywords(d.name), "(", typeCode, " value) nothrow");
                code.writeln("{").incIndent;
                code.writeln(e.data.dataName, " = (", e.data.dataName,
                        " & ~", hexMaskCode(e.data.length, e.data.firstBit),
                        ") | ((value & ", hexMaskCode(e.data.length, 0),
                        ") << ", e.data.firstBit, ");");
                code.writeln("return value;");
                code.decIndent.writeln("}");
            }

            if (closeBraces)
                code.writeln("}");
        }
    }
    else if (d.type == DeclarationType.varOrFunc
            && !d.tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal", "LambdaExpression") && (d.flags & DeclarationFlags.function_) == 0)
    {
        Tree findPrevSeperator(Tree t)
        {
            if (t.nodeType == NodeType.token)
            {
                if (t.start < d.declaratorTree.start)
                    return t;
            }
            else if (t.nodeType == NodeType.array
                    || t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                Tree r;
                foreach (c; t.childs)
                {
                    auto tmp = findPrevSeperator(c);
                    if (tmp.isValid)
                        r = tmp;
                }
                return r;
            }
            return Tree.init;
        }

        Tree prevSeparator = findPrevSeperator(d.tree.childByName("declarators"));
        if (prevSeparator.isValid)
            writeComments(code, data, d.declaratorTree.start);

        ConditionMap!string codeType;
        CodeWriter codeAfterDeclSeq;
        codeAfterDeclSeq.indentStr = data.options.indent;
        bool afterTypeInDeclSeq;
        //if (data.sourceTokenManager.tokensLeft.data.length > 0)
        {
            if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration1",
                    "SimpleDeclaration3", "MemberDeclaration1",
                    "ParameterDeclaration", "Condition",
                    "ForRangeDeclaration", "ExceptionDeclaration"))
            {
                collectDeclSeqTokens(code, codeType, codeAfterDeclSeq,
                        afterTypeInDeclSeq, d.tree.childs[0], condition2, data, currentScope);
                if (d.declaratorTree.isValid)
                    writeComments(codeAfterDeclSeq, data, d.declaratorTree.start);
                else
                    writeComments(codeAfterDeclSeq, data, d.tree.childs[1].start);
            }
            else if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration2"))
            {
            }
            else
                assert(false, text(d.tree.name, " ", locationStr(d.tree.location)));
        }
        Tree realDeclarator = d.declaratorTree;
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"InitDeclarator")
            realDeclarator = realDeclarator.childs[0];
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"MemberDeclarator")
            realDeclarator = realDeclarator.childs[0];

        string typeCode = typeToCode(d.type2, data, condition2, currentScope, d.location,
                declaratorList(realDeclarator, d.condition, data, currentScope), codeType);
        typeCode ~= codeAfterDeclSeq.data;

        bool isArrayWithoutSize;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            auto t = chooseType(d.type2, ppVersion, true);

            if (t.type !is null && t.kind == TypeKind.array)
            {
                auto atype = cast(ArrayType) t.type;
                if (!atype.declarator.childs[2].isValid)
                {
                    isArrayWithoutSize = true;
                }
            }
        }

        bool hasInitializer = d.declaratorTree.nonterminalID == nonterminalIDFor!"InitDeclarator"
            || (d.declaratorTree.nonterminalID == nonterminalIDFor!"MemberDeclarator"
                    && d.declaratorTree.childs.length == 2);

        if ((d.flags & DeclarationFlags.extern_) != 0)
        {
            code.write("extern ");
        }
        if ((d.flags & DeclarationFlags.static_) != 0)
        {
            if (d.scope_ == semantic.rootScope || !d.scope_.tree.isValid
                    || d.scope_.tree.name != "ClassSpecifier" || hasInitializer)
                code.write("extern(D) static ");
            else
                code.write("extern static ");
        }

        if (d.flags & DeclarationFlags.constExpr)
            code.write("immutable ");
        else if (d.scope_.isRootNamespaceScope || (d.flags & DeclarationFlags.static_) != 0)
            code.write("__gshared ");

        if (d.declaratorTree.nameOrContent == "InitDeclarator"
                && d.declaratorTree.childs[$ - 1].childs[0].nameOrContent == "(")
            code.write("auto");
        else if (isArrayWithoutSize
                && d.declaratorTree.nonterminalID == nonterminalIDFor!"InitDeclarator")
            code.write("/+ ", typeCode, " +/ auto");
        else
            code.write(typeCode);

        if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
            code.write(" ");
        code.write(chooseDeclarationName(d, data));
        if (d.declaratorTree.name != "InitDeclarator" && d in semantic.declarationExtra2Map)
        {
            auto declarationExtra2 = &semantic.declarationExtra2(d);
            if (declarationExtra2.defaultInit.entries.length > 1)
            {
                code.write(" /* = TODO*/");
            }
            else if (declarationExtra2.defaultInit.entries.length)
            {
                enforce(declarationExtra2.defaultInit.entries.length == 1, text(locationStr(d.tree.location)));
                auto e = declarationExtra2.defaultInit.entries[0];
                enforce(semantic.logicSystem.and(condition2, e.condition.negated)
                        .isFalse, text(d.name, " ", locationStr(d.location),
                            " ", condition2.toString, " ", e.condition.toString));
                auto bak = saveCodeTokenInfo(code, data);
                if (e.data.childs.length == 4 && e.data.childs[2].isValid
                        && e.data.childs[2].childs.length)
                {
                    code.write(" = ");
                    parseTreeToDCode(code, data, e.data.childs[2], condition2, currentScope);
                }
                else
                {
                    code.write(" /* = TODO*/");
                }
                restoreCodeTokenInfoBak(code, data, bak);
            }
        }
        if (d.declaratorTree.nameOrContent == "InitDeclarator"
                && d.declaratorTree.childs[$ - 1].childs[0].nameOrContent == "(")
        {
            while (typeCode.length && typeCode[$ - 1] == ' ')
                typeCode = typeCode[0 .. $ - 1];
            code.write(" = ", typeCode);
        }
        if (d.declaratorTree.nonterminalID == nonterminalIDFor!"InitDeclarator")
        {
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(code, data, d.declaratorTree.childs[1].start, true);
            bool hasSelfReference;
            void checkSelfReference(Tree t)
            {
                if (!t.isValid)
                    return;
                if (t.nodeType == NodeType.nonterminal
                        && t.nonterminalID == nonterminalIDFor!"NameIdentifier")
                {
                    foreach (x; semantic.extraInfo(t).referenced.entries)
                        foreach (e; x.data.entries)
                        {
                            if (e.data is d)
                            {
                                hasSelfReference = true;
                            }
                        }
                }
                foreach (c; t.childs)
                    checkSelfReference(c);
            }

            checkSelfReference(d.declaratorTree.childs[1]);

            if (hasSelfReference)
            {
                code.writeln(";");
                code.write(replaceKeywords(d.name));
            }

            code.customIndent = origCustomIndent;
            parseTreeToDCode(code, data, d.declaratorTree.childs[1], condition2, currentScope);
            code.customIndent = newCustomIndent;
        }
        else if (d.declaratorTree.nonterminalID == nonterminalIDFor!"MemberDeclarator"
                && d.declaratorTree.childs.length == 2)
        {
            code.customIndent = origCustomIndent;
            parseTreeToDCode(code, data,
                    d.declaratorTree.childByName("initializer"), condition2, currentScope);
            code.customIndent = newCustomIndent;
        }
        else
        {
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(code, data, d.declaratorTree.end, true);
        }
        if (d.tree.nonterminalID == nonterminalIDFor!"Condition"
                || (d.tree.nonterminalID == nonterminalIDFor!"ParameterDeclaration"
                    && d.tree.childs.length == 4))
        {
            code.customIndent = origCustomIndent;
            // Add initializer
            foreach (c; d.tree.childs[2 .. $])
                parseTreeToDCode(code, data, c, condition2, currentScope);
            code.customIndent = newCustomIndent;
        }
        Tree findNextEndToken(Tree t)
        {
            if (t.nodeType == NodeType.token)
            {
                if (t.start >= d.declaratorTree.start)
                    return t;
            }
            else if (t.nodeType == NodeType.array || t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                foreach (c; t.childs)
                {
                    auto r = findNextEndToken(c);
                    if (r.isValid)
                        return r;
                }
            }
            return Tree.init;
        }

        Tree nextEndToken = findNextEndToken(d.tree.childByName("declarators"));
        if (!nextEndToken.isValid && d.tree.nameOrContent != "ParameterDeclaration"
                && d.tree.childs[$ - 1].nameOrContent == ";")
            nextEndToken = d.tree.childs[$ - 1];
        if (nextEndToken.isValid)
            skipToken(code, data, nextEndToken);
        if (!d.tree.nonterminalID.nonterminalIDAmong!("Condition", "ParameterDeclaration", "ForRangeDeclaration", "ExceptionDeclaration"))
            code.write(";");
        if (nextEndToken.isValid && data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data,
                    data.sourceTokenManager.collectTokensUntilLineEnd(nextEndToken.location.end,
                        condition2));
        else if (!d.tree.nonterminalID.nonterminalIDAmong!("Condition", "ParameterDeclaration", "ForRangeDeclaration", "ExceptionDeclaration"))
            code.writeln();
    }
    else if (d.type == DeclarationType.varOrFunc
            && (d.tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal", "LambdaExpression") || (d.flags & DeclarationFlags.function_) != 0))
    {
        DeclarationFlags combinedFlags = d.flags;
        bool hasFunctionBody = d.tree.name.startsWith("FunctionDefinition") || d.tree.nonterminalID.nonterminalIDAmong!("LambdaExpression");
        if (hasFunctionBody && d.tree.childs.length == 4 && d.tree.childs[2].content == "delete")
            hasFunctionBody = false;
        if (d.scope_ !is semantic.rootScope)
        {
            foreach (e; d.realDeclaration.entries)
            {
                if (e.data.scope_ !is semantic.rootScope)
                    continue;
                combinedFlags |= e.data.flags;
                auto bak = saveCodeTokenInfo(code, data);
                declarationToDCodeBefore(code, data, e.data, condition, d, true);
                restoreCodeTokenInfoBak(code, data, bak);
                hasFunctionBody = true;
            }
        }
        if (forwardDecl !is null)
            combinedFlags |= forwardDecl.flags;

        QualType resultType = filterType(functionResultType(d.type2, semantic), condition, semantic);

        string operatorFunctionName, operatorTemplateConstraint;
        bool commentWholeDecl;
        bool addExternD;
        if (d.name == "operator cast")
        {
            if (resultType.kind != TypeKind.builtin || resultType.name != "bool")
                commentWholeDecl = true;
        }
        else if (d.name.startsWith("operator "))
        {
            if (d.name == "operator =" && forwardDecl is null && !hasFunctionBody)
            {
                if (!isStruct(parentClassTree, data))
                    return;
            }
            string op = d.name["operator ".length .. $];
            QualType type2 = filterType(d.type2, condition, semantic);
            if (type2.kind == TypeKind.function_)
            {
                auto functionType = cast(FunctionType) type2.type;
                if (op.among("++", "--", "*", "+", "-", "~")
                        && functionType.parameters.length == 0 && parentClassTree.isValid)
                {
                    operatorFunctionName = "opUnary(string op)";
                    operatorTemplateConstraint = " if (op == \"" ~ op ~ "\")";
                }
                if (op.among("&", "|", "+", "-", "*", "/", "%", "^")
                        && functionType.parameters.length == 1 && parentClassTree.isValid)
                {
                    if (op == "+" && lastDeclaration !is null
                            && data.options.arrayLikeTypes.canFind(lastDeclaration.name))
                    {
                        op = "~";
                        addExternD = true;
                    }
                    operatorFunctionName = "opBinary(string op)";
                    operatorTemplateConstraint = " if (op == \"" ~ op ~ "\")";
                }
                if (op == "="
                        && functionType.parameters.length == 1 && parentClassTree.isValid)
                {
                    operatorFunctionName = "opAssign";
                }
                if (op.among("&=", "|=", "+=", "-=", "*=", "/=", "%=", "^=")
                        && functionType.parameters.length == 1 && parentClassTree.isValid)
                {
                    if (op == "+=" && lastDeclaration !is null
                            && data.options.arrayLikeTypes.canFind(lastDeclaration.name))
                    {
                        op = "~=";
                        addExternD = true;
                    }
                    operatorFunctionName = "opOpAssign(string op)";
                    operatorTemplateConstraint = " if (op == \"" ~ op[0 .. $ - 1] ~ "\")";
                }
                if (op.among("[]") && functionType.parameters.length == 1 && parentClassTree
                        .isValid)
                {
                    operatorFunctionName = "opIndex";
                }
            }
            if (operatorFunctionName.length == 0)
            {
                commentWholeDecl = true;
            }
        }

        bool isConstructor, isDestructor;
        if (lastDeclaration !is null && lastDeclaration.type == DeclarationType.type
                && d.name.startsWith("$norettype:"))
        {
            if (d.name == "$norettype:" ~ lastDeclaration.name)
                isConstructor = true;
            if (d.name == "$norettype:" ~ "~" ~ lastDeclaration.name)
                isDestructor = true;
        }

        bool inAbstractClass;
        if (lastDeclaration !is null && lastDeclaration.type == DeclarationType.type)
            inAbstractClass = data.declarationData(lastDeclaration).isAbstractClass;

        bool noParameters = true;
        bool noParametersPossible = false;
        bool isCopyConstructor = false;
        bool hasTailConstClass = false;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, semantic.logicSystem.and(d.condition, condition), null, semantic.mergedTreeDatas);
            QualType t = chooseType(d.type2, ppVersion, false);
            if (t.kind != TypeKind.function_)
                continue;
            assert(t.kind == TypeKind.function_);
            FunctionType ftype = cast(FunctionType) t.type;
            if (ftype.parameters.length)
                noParameters = false;
            if (ftype.neededParameters == 0)
                noParametersPossible = true;

            if (isConstructor && ftype.neededParameters == 1)
            {
                QualType p0 = chooseType(ftype.parameters[0], ppVersion, true);
                if (p0.kind == TypeKind.reference)
                {
                    p0 = chooseType((cast(ReferenceType) p0.type).next, ppVersion, true);
                    if (p0.kind == TypeKind.record)
                    {
                        foreach (d2; semantic.extraInfo(findWrappingDeclaration(d.scope_.tree,
                                semantic)).declarations)
                        {
                            if (d2.declarationSet is(cast(RecordType) p0.type).declarationSet)
                                isCopyConstructor = true;
                        }
                    }
                }
            }
            foreach (p; ftype.parameters)
            {
                QualType t2 = chooseType(p, ppVersion, true);
                if (t2.qualifiers & Qualifiers.const_)
                    continue;
                if (t2.kind != TypeKind.pointer)
                    continue;
                PointerType pointerType = cast(PointerType) t2.type;
                QualType t3 = chooseType(pointerType.next, ppVersion, true);
                if ((t3.qualifiers & Qualifiers.const_) == 0)
                    continue;
                if (t3.kind != TypeKind.record)
                    continue;
                if (!isInCorrectVersion(ppVersion, typeIsClass(t3, data)))
                    continue;
                hasTailConstClass = true;
            }
            {
                QualType t2 = chooseType(ftype.resultType, ppVersion, true);
                if (t2.qualifiers & Qualifiers.const_)
                    continue;
                if (t2.kind != TypeKind.pointer)
                    continue;
                PointerType pointerType = cast(PointerType) t2.type;
                QualType t3 = chooseType(pointerType.next, ppVersion, true);
                if ((t3.qualifiers & Qualifiers.const_) == 0)
                    continue;
                if (t3.kind != TypeKind.record)
                    continue;
                if (!isInCorrectVersion(ppVersion, typeIsClass(t3, data)))
                    continue;
                hasTailConstClass = true;
            }
        }

        if (forwardDecl is null && isCopyConstructor)
        {
            if (isStruct(parentClassTree, data))
            {
                code.writeln("@disable this(this);");
                if (d.tree.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
                        && d.tree.childs.length == 4 && d.tree.childs[2].content == "delete")
                    commentWholeDecl = true;
            }
            else if (!hasFunctionBody)
                return;
            else
                commentWholeDecl = true;
        }
        bool useRawConstructor;
        if (isConstructor && isStruct(parentClassTree, data))
        {
            if (noParameters)
            {
                if (!hasFunctionBody || data.options.arrayLikeTypes.canFind(lastDeclaration.name))
                    useRawConstructor = true;
            }
        }
        if (forwardDecl is null && isConstructor && isStruct(parentClassTree, data))
        {
            if (noParametersPossible)
                code.writeln("@disable this();");
            if (noParameters && !useRawConstructor)
                commentWholeDecl = true;
        }

        if (commentWholeDecl && forwardDecl is null)
            code.write("/+");
        scope (success)
            if (commentWholeDecl && forwardDecl is null)
                code.write("+/");

        string addedAttributes;

        string changeMangleFuncs;
        bool changeMangleWin, changeMangleItanium;
        if (hasTailConstClass)
        {
            changeMangleFuncs ~= ".mangleClassesTailConst";
            changeMangleWin = true;
        }
        if (inAbstractClass && isConstructor)
        {
            changeMangleFuncs ~= ".mangleConstructorBaseObject";
            changeMangleItanium = true;
        }
        if (parentClassTree.isValid && (forwardDecl2.flags & DeclarationFlags.static_) == 0
                && !isClass(parentClassTree, data) && !isConstructor)
        {
            if ((forwardDecl2.flags & DeclarationFlags.override_) || (forwardDecl2.flags & DeclarationFlags.virtual)
                    || (isDestructor && data.currentFilename.moduleName.startsWith("qt.")
                        && lastDeclaration.name.among("QImage", "QPixmap", "QPicture")))
            {
                changeMangleFuncs ~= ".mangleChangeFunctionType(\"virtual\")";
                changeMangleWin = true;
            }
        }

        if (parentClassTree.isValid && (forwardDecl2.flags & DeclarationFlags.static_) == 0
                && isClass(parentClassTree, data) && !isConstructor && !isDestructor && !hasFunctionBody && !commentWholeDecl)
        {
            if ((forwardDecl2.flags & DeclarationFlags.override_) || forwardDecl2.flags & DeclarationFlags.virtual)
            {
                bool isPrivate;
                foreach (e; semantic.extraInfo2(forwardDecl2.tree).accessSpecifier.entries)
                {
                    if ((e.data & AccessSpecifier.private_) == 0)
                        continue;
                    if (!logicSystem.and(e.condition, condition2).isFalse)
                    {
                        auto econdition2 = removeLocationInstanceConditions(e.condition,
                                logicSystem, data.mergedFileByName);
                        enforce(logicSystem.and(econdition2.negated, condition2).isFalse,
                                text(locationStr(d.location), "\n", e.condition.toString, "\n",
                                    condition2.toString, "\n",
                                    logicSystem.and(e.condition.negated, condition2).toString));
                        isPrivate = true;
                    }
                }

                if (isPrivate)
                {
                    /*
                    Virtual functions can not be private in D, but they need to be mangled
                    as private on Windows.
                    */
                    addedAttributes ~= "protected ";
                    changeMangleFuncs ~= ".mangleChangeAccess(\"private\")";
                    changeMangleWin = true;
                }
            }
        }

        if (forwardDecl !is null || hasFunctionBody || commentWholeDecl)
        {
            changeMangleFuncs = "";
        }
        if (changeMangleFuncs.length)
            code.writeln("mixin(change", (changeMangleWin && changeMangleItanium) ? "Cpp" : changeMangleWin
                    ? "Windows" : "Itanium", "Mangling(q{", changeMangleFuncs[1 .. $], "}, q{");
        scope (success)
        {
            if (changeMangleFuncs.length)
            {
                if (code.inLine)
                {
                    code.writeln();
                    code.write("}));");
                }
                else
                    code.writeln("}));");
            }
        }

        if (d.tree.nonterminalID.nonterminalIDAmong!("LambdaExpression")
            && d.tree.childs[0].nonterminalID.nonterminalIDAmong!("LambdaDeclarator"))
        {
            writeComments(code, data, d.tree.childs[0].childs[0].end);
        }

        bool hasRealDecl;
        if (d.scope_ !is semantic.rootScope && d.realDeclaration.conditionAll !is null
                && !logicSystem.and(d.condition, d.realDeclaration.conditionAll).isFalse)
        {
            enforce(logicSystem.and(d.condition, d.realDeclaration.conditionAll.negated)
                    .isFalse, text(d.name, " ", locationStr(d.location), " ",
                        d.condition.toString, "\n  ", d.realDeclaration.conditionAll.toString));
            hasRealDecl = true;
        }
        CodeWriter* codeTmp = &code;
        CodeWriter codeForward;
        codeForward.indentStr = data.options.indent;
        size_t functionCodeStart = code.data.length;
        if (forwardDecl !is null)
        {
            codeTmp = &codeForward;
        }

        ConditionMap!string codeType;
        CodeWriter codeAfterDeclSeq;
        codeAfterDeclSeq.indentStr = data.options.indent;
        bool afterTypeInDeclSeq;
        //if (data.sourceTokenManager.tokensLeft.data.length > 0)
        {
            if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration1",
                    "SimpleDeclaration3", "MemberDeclaration1",
                    "ParameterDeclaration", "Condition",
                    "ForRangeDeclaration", "ExceptionDeclaration"))
            {
                collectDeclSeqTokens(*codeTmp, codeType, codeAfterDeclSeq,
                        afterTypeInDeclSeq, d.tree.childs[0], condition2, data, currentScope);
                writeComments(codeAfterDeclSeq, data, d.tree.childs[1].start);
            }
            else if (d.tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                    "FunctionDefinitionGlobal"))
            {
                if (d.tree.childs[0].nonterminalID == CONDITION_TREE_NONTERMINAL_ID
                        || d.tree.childs[0].nodeType == NodeType.merged)
                {
                    foreach (c; d.tree.childs[0].childs)
                    {
                        assert(c.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead",
                                text(c.name, " ", locationStr(d.tree.location), "  ", d.tree));
                        collectDeclSeqTokens(*codeTmp, codeType, codeAfterDeclSeq,
                                afterTypeInDeclSeq, c.childs[0], condition2, data, currentScope);
                        writeComments(codeAfterDeclSeq, data, c.childs[1].start);
                    }
                }
                else
                {
                    assert(d.tree.childs[0].nonterminalID == nonterminalIDFor!"FunctionDefinitionHead");
                    collectDeclSeqTokens(*codeTmp, codeType, codeAfterDeclSeq, afterTypeInDeclSeq,
                            d.tree.childs[0].childs[0], condition2, data, currentScope);
                    writeComments(codeAfterDeclSeq, data, d.tree.childs[0].childs[1].start);
                }
            }
            else if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration2", "LambdaExpression"))
            {
            }
            else
                assert(false, d.tree.name);
        }

        Tree realDeclarator = d.declaratorTree;
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"InitDeclarator")
            realDeclarator = realDeclarator.childs[0];
        if (realDeclarator.isValid
                && realDeclarator.nonterminalID == nonterminalIDFor!"MemberDeclarator")
            realDeclarator = realDeclarator.childs[0];

        if (useRawConstructor && !hasFunctionBody)
            code.writeln(
                    "pragma(mangle, defaultConstructorMangling(__traits(identifier, typeof(this))))");

        if (addExternD)
        {
            codeTmp.write("extern(D) ");
        }

        if (combinedFlags & DeclarationFlags.inline)
        {
            codeTmp.write("pragma(inline, true) ");
        }

        foreach (e; semantic.extraInfo2(forwardDecl2.tree).accessSpecifier.entries)
        {
            if ((e.data & (AccessSpecifier.qtSignal | AccessSpecifier.qtSlot
                    | AccessSpecifier.qtInvokable | AccessSpecifier.qtScriptable)) == 0)
                continue;
            if (!logicSystem.and(e.condition, condition2).isFalse)
            {
                auto econdition2 = removeLocationInstanceConditions(e.condition,
                        logicSystem, data.mergedFileByName);
                enforce(logicSystem.and(econdition2.negated, condition2).isFalse,
                        text(locationStr(d.location), "\n", e.condition.toString, "\n",
                            condition2.toString, "\n",
                            logicSystem.and(e.condition.negated, condition2).toString));
                if (e.data & AccessSpecifier.qtSignal)
                    codeTmp.write("@QSignal ");
                if (e.data & AccessSpecifier.qtSlot)
                    codeTmp.write("@QSlot ");
                if (e.data & AccessSpecifier.qtInvokable)
                    codeTmp.write("@QInvokable ");
                if (e.data & AccessSpecifier.qtScriptable)
                    codeTmp.write("@QScriptable ");
            }
        }

        if (d.tree.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
                && d.tree.childs.length == 4 && d.tree.childs[2].content == "delete")
        {
            codeTmp.write("@disable ");
        }

        codeTmp.write(addedAttributes);

        if (parentClassTree.isValid && (forwardDecl2.flags & DeclarationFlags.static_) != 0)
        {
            codeTmp.write("static ");
        }

        if (d.flags & DeclarationFlags.abstract_)
        {
            codeTmp.write("abstract ");
        }

        if (parentClassTree.isValid && (forwardDecl2.flags & DeclarationFlags.static_) == 0
                && isClass(parentClassTree, data) && !isConstructor)
        {
            string parentClassMangling;
            if (data.currentClassDeclaration !is null)
            {
                Scope classScope = data.currentClassDeclaration.scope_.childScopeByTree[data.currentClassDeclaration.tree];
                foreach (e; classScope.extraParentScopes.entries)
                {
                    if (e.data.type != ExtraScopeType.parentClass)
                        continue;
                    if (semantic.logicSystem.and(e.condition, condition).isFalse)
                        continue;
                    Tree parent1 = getRealParent(e.data.scope_.tree, data.semantic);
                    if (!parent1.isValid)
                        continue;
                    Tree parent2 = getRealParent(parent1, data.semantic);
                    if (!parent2.isValid)
                        continue;
                    foreach (d2; data.semantic.extraInfo(parent2).declarations)
                    {
                        if (d2.tree !is e.data.scope_.tree)
                            continue;
                        parentClassMangling = getDefaultMangling(data, getDeclarationFilename(d2, data));
                    }
                }
            }
            if (forwardDecl2.flags & DeclarationFlags.override_)
            {
                if (!isDestructor && getDefaultMangling(data, data.currentFilename) == "D" && parentClassMangling == "C++")
                    codeTmp.write("extern(C++) ");
                if (forwardDecl2.flags & DeclarationFlags.final_)
                {
                    codeTmp.write("final ");
                }
                if (!isDestructor)
                    codeTmp.write("override ");
            }
            else if (forwardDecl2.flags & DeclarationFlags.virtual)
            {
            }
            else if (!isDestructor)
                codeTmp.write("final ");
        }

        DeclaratorData[] declList = declaratorList(realDeclarator, d.condition, data, currentScope,
                isConstructor && parentClassTree.isValid && isStruct(parentClassTree, data));

        DeclaratorData[] declList2 = declList;
        while (declList2.length && ((declList2[0].tree.nonterminalID == nonterminalIDFor!"NoptrDeclarator"
                && declList2[0].tree.childs.length == 4) || declList2[0].tree.name
                == "PtrDeclarator"))
            declList2 = declList2[1 .. $];
        if (declList2.length)
        {
            assert(declList2[0].tree.nonterminalID.nonterminalIDAmong!("FunctionDeclarator",
                    "FunctionDeclaratorTrailing", "LambdaDeclarator"), text(declList2[0].tree.name,
                    " ", locationStr(declList2[0].tree.start)));
            declList2 = declList2[1 .. $];
        }

        if (isConstructor || isDestructor)
        {
            //assert(declList2.length == 0, text(locationStr(d.tree.location), " ", declList2));
            //codeTmp.write(codeAfterDeclSeq.data);
        }
        else if (d.tree.nonterminalID.nonterminalIDAmong!("LambdaExpression"))
        {
        }
        else if (d.name == "operator cast")
        {
            codeTmp.write(codeAfterDeclSeq.data);
            codeTmp.write("auto ");
        }
        else
        {
            string typeCode = typeToCode(resultType, data, condition2,
                    currentScope, d.location, declList2, codeType) ~ codeAfterDeclSeq.data.idup;

            codeTmp.write(typeCode);
            if (codeTmp.inLine && codeTmp.data.length && !codeTmp.data[$ - 1].inCharSet!" \t")
                codeTmp.write(" ");
        }
        if (isConstructor)
        {
            if (useRawConstructor)
                codeTmp.write("void rawConstructor");
            else
                codeTmp.write("this");
        }
        else if (isDestructor)
            codeTmp.write("~this");
        else if (d.name == "operator cast")
        {
            codeTmp.write("opCast(T : ");

            string typeCode = typeToCode(resultType, data,
                    condition2, currentScope, d.location, declList2, codeType);
            codeTmp.write(typeCode);
            codeTmp.write(")");
        }
        else if (operatorFunctionName.length)
            codeTmp.write(operatorFunctionName);
        else
            codeTmp.write(chooseDeclarationName(forwardDecl2, data));

        if (templateParamCodeWriter.data.length)
        {
            if (forwardDecl is null)
                codeTmp.write("(", templateParamCodeWriter.data, ")");
            data.declarationData(d).templateParamCode = "";
        }

        if (declList.length)
            codeTmp.write(declList[0].codeBefore);
        parseTreeToCodeTerminal(*codeTmp, "(");
        if (declList.length)
            codeTmp.write(declList[0].codeMiddle);
        parseTreeToCodeTerminal(*codeTmp, ")");
        if (declList.length)
            codeTmp.write(declList[0].codeAfter);
        codeTmp.write(operatorTemplateConstraint);

        if (d.tree.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
                && d.tree.childs.length == 4 && d.tree.childs[2].content == "0")
        {
            skipToken(code, data, d.tree.childs[1], false, true);
            skipToken(code, data, d.tree.childs[2], false, true);
        }
        if (d.tree.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
                && d.tree.childs.length == 4 && d.tree.childs[2].content == "delete")
        {
            skipToken(code, data, d.tree.childs[1], false, true);
            skipToken(code, data, d.tree.childs[2], false, true);
        }

        if (forwardDecl !is null)
        {
            if (!codeTmp.data.idup.isSubCode(data.declarationData(forwardDecl)
                    .functionPrototypeCode))
            {
                if (code.inLine)
                    code.writeln();
                code.write("/+");
                code.write(codeTmp.data);
                code.write("+/");
            }
        }

        data.declarationData(d).functionPrototypeCode = code.data[functionCodeStart .. $].idup;

        code.customIndent = origCustomIndent;
        if (d.tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal", "LambdaExpression"))
            parseTreeToDCode(code, data, d.tree.childs[$ - 1], condition2, currentScope);
        else if (hasRealDecl)
            skipToken(code, data, d.tree.childs[$ - 1]);
        else
        {
            skipToken(code, data, d.tree.childs[$ - 1]);
            code.write(";");
        }
        code.customIndent = newCustomIndent;

        if (d.scope_ !is semantic.rootScope)
        {
            foreach (e; d.realDeclaration.entries)
            {
                if (e.data.scope_ !is semantic.rootScope)
                    continue;
                data.currentDeclaration = lastDeclaration;

                declarationToDCode2Bak(code, data, e.data,
                        logicSystem.and(condition, e.condition), d);
            }
        }

        if (useRawConstructor && forwardDecl is null)
        {
            if (code.inLine)
                code.writeln();
            code.writeln("static typeof(this) create()");
            code.writeln("{").incIndent;
            code.writeln("typeof(this) r = typeof(this).init;");
            code.writeln("r.rawConstructor();");
            code.writeln("return r;");
            code.decIndent.writeln("}");
        }
    }
    else if (d.type == DeclarationType.type
            && d.tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier"
            && d.tree.hasChildWithName("name"))
    {
        if (d.scope_ !is semantic.rootScope)
        {
            foreach (e; d.realDeclaration.entries)
            {
                if (e.data.scope_ !is semantic.rootScope)
                    continue;
                auto declarationData2 = data.declarationData(e.data);
                if (declarationData2.movedDeclDone is null)
                    declarationData2.movedDeclDone = logicSystem.false_;
                if (logicSystem.and(declarationData2.movedDeclDone.negated,
                        logicSystem.and(condition, e.condition)).isFalse)
                    continue;

                auto bak = saveCodeTokenInfo(code, data);
                declarationToDCodeBefore(code, data, e.data, condition, d, true);
                restoreCodeTokenInfoBak(code, data, bak);
            }
        }

        string name = chooseDeclarationName(d, data);

        bool closeComment;
        if (d.scope_ !is semantic.rootScope && d.realDeclaration.conditionAll !is null
                && logicSystem.and(d.condition, d.realDeclaration.conditionAll.negated).isFalse)
        {
            code.writeln("/+");
            closeComment = true;
        }

        foreach (i, c; d.tree.childs)
        {
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                if (c.isValid)
                    writeComments(code, data, c.start);
            if (d.tree.childName(i) == "attr")
                continue;
            if (d.tree.childName(i) == "name")
            {
                if (name.length)
                {
                    if (code.inLine && code.data.length && !code.data[$ - 1].inCharSet!" \t")
                        code.write(" ");
                    code.write(name);
                    if (data.sourceTokenManager.tokensLeft.data.length > 0)
                        data.sourceTokenManager.collectTokens(c.end);
                }
            }
            if (d.tree.childName(i) != "name")
                parseTreeToDCode(code, data, c, condition, currentScope);
        }
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data, d.tree.end);
        code.write(";");

        if (closeComment)
            code.writeln().write("+/");

        if (d.scope_ !is semantic.rootScope)
        {
            foreach (e; d.realDeclaration.entries)
            {
                if (e.data.scope_ !is semantic.rootScope)
                    continue;
                auto declarationData2 = data.declarationData(e.data);
                if (declarationData2.movedDeclDone is null)
                    declarationData2.movedDeclDone = logicSystem.false_;
                if (logicSystem.and(declarationData2.movedDeclDone.negated,
                        logicSystem.and(condition, e.condition)).isFalse)
                    continue;
                declarationData2.movedDeclDone = logicSystem.or(declarationData2.movedDeclDone,
                        logicSystem.and(condition, e.condition));

                data.currentDeclaration = lastDeclaration;

                declarationToDCode2Bak(code, data, e.data,
                        logicSystem.and(condition, e.condition), d);
            }
        }
    }
    else if (d.type == DeclarationType.type
            && d.tree.nonterminalID == nonterminalIDFor!"EnumSpecifier")
    {
        auto tree = d.tree;

        auto codeWrapper = ConditionalCodeWrapper(condition2, data);

        codeWrapper.checkTree(tree.childs[2 .. $ - 1], false);

        if (codeWrapper.alwaysUseMixin)
        {
            codeWrapper.begin(code, condition2);

            void onTree(Tree t, immutable(Formula)* condition2)
            {
                code.customIndent = origCustomIndent;
                parseTreeToDCode(code, data, t, condition2, currentScope);
                writeComments(code, data, data.sourceTokenManager.collectTokens(t.location.end));
                writeComments(code, data,
                        data.sourceTokenManager.collectTokensUntilLineEnd(t.location.end,
                            condition));
                code.customIndent = newCustomIndent;
            }

            code.incIndent;
            codeWrapper.writeTree(code, &onTree, tree.childs[0]);
            skipToken(code, data, tree.childs[1]);
            codeWrapper.writeString(code, "{");
            codeWrapper.writeTree(code, &onTree, tree.childs[2 .. $ - 1]);
            skipToken(code, data, tree.childs[$ - 1]);
            codeWrapper.writeString(code, "}");
            code.decIndent;

            codeWrapper.end(code, condition2);
            code.write(";");
        }
        else
        {
            code.customIndent = origCustomIndent;
            foreach (c; tree.childs)
                parseTreeToDCode(code, data, c, condition2, currentScope);
            code.customIndent = newCustomIndent;
        }
    }
    else if (d.type == DeclarationType.type
            && d.tree.nonterminalID == nonterminalIDFor!"ClassSpecifier")
    {
        auto oldClassDeclaration = data.currentClassDeclaration;
        data.currentClassDeclaration = d;
        scope (success)
            data.currentClassDeclaration = oldClassDeclaration;

        bool hasMethod;
        bool hasAbstractMethod;
        outer: foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, semantic.logicSystem.true_, null, semantic.mergedTreeDatas);
            if (auto childScope = d.tree in d.scope_.childScopeByTree)
            {
                Scope classScope = *childScope;
                foreach (name, ds; classScope.symbols)
                {
                    foreach (e; ds.entries)
                    {
                        if (e.data.flags & DeclarationFlags.function_)
                        {
                            hasMethod = true;
                            if (e.data.flags & DeclarationFlags.abstract_)
                            {
                                hasAbstractMethod = true;
                            }
                        }
                    }
                }
            }
        }
        foreach_reverse (ref pattern; data.options.abstractClasses)
        {
            DeclarationMatch match;
            if (isDeclarationMatch(pattern, match, d, semantic))
            {
                hasAbstractMethod = true;
                break;
            }
        }
        data.declarationData(d).isAbstractClass = hasAbstractMethod;

        data.declarationData(d).extraAttributes.sort!((a, b) {
            if (a.startsWith("(") && !b.startsWith("("))
                return false;
            if (!a.startsWith("(") && b.startsWith("("))
                return true;
            return a < b;
        })();
        foreach (a; data.declarationData(d).extraAttributes)
            code.write("@", a, " ");

        if (hasAbstractMethod)
            code.write("abstract ");

        parseTreeToDCode(code, data, d.tree.childs[0], condition2, currentScope);

        ClassAttributes attributes;
        analyzeClassAttributes(d.tree.childs[0], condition2, semantic, attributes);

        assert(d.tree.childs[1].nonterminalID == nonterminalIDFor!"ClassBody");
        code.customIndent = origCustomIndent;
        parseTreeToDCode(code, data, d.tree.childs[1].childs[0], condition2, currentScope);
        code.customIndent = newCustomIndent;

        if (data.sourceTokenManager.tokensLeft.data.length)
        {
            auto endTokens = data.sourceTokenManager.collectTokensUntilLineEnd(
                    d.tree.childs[1].childs[0].location.end, condition2);
            writeComments(code, data, endTokens);
        }

        foreach (e; attributes.pack.entries)
        {
            if (e.condition !is condition2)
                code.writeln("static if (", conditionToDCode(e.condition, data), ")");
            code.writeln("align(", e.data, "):");
        }

        foreach (i, e; data.declarationData(d).structBaseclasses.entries)
        {
            if (code.inLine)
                code.writeln();
            code.incIndent;
            if (e.condition !is condition2)
                code.writeln("static if (", conditionToDCode(e.condition, data), ")");
            code.writeln(e.data, " base", i, ";");
            if (i == 0)
                code.writeln("alias base", i, " this;");
            code.decIndent;
        }

        if (attributes.classKey == "class"
                && d.tree.childs[1].childs[1].isValid
                && d.tree.childs[1].childs[1].childs.length
                && !(d.tree.childs[1].childs[1].nodeType == NodeType.array
                    && d.tree.childs[1].childs[1].childs.length
                    && d.tree.childs[1].childs[1].childs[0].nonterminalID
                    == nonterminalIDFor!"AccessSpecifierWithColon"))
        {
            if (code.inLine)
                code.writeln();
            code.writeln("private:");
        }

        assert(d.tree.childs[1].nonterminalID == nonterminalIDFor!"ClassBody");
        code.customIndent = origCustomIndent;
        parseTreeToDCode(code, data, d.tree.childs[1].childs[1], condition2, currentScope);
        writeComments(code, data, d.tree.childs[1].childs[2].start);
        code.startLine();

        if (hasMethod && d.scope_ is semantic.rootScope)
        {
            string classSuffixCode;
            foreach_reverse (ref pattern; data.options.classSuffixCode)
            {
                DeclarationMatch match;
                if (isDeclarationMatch(pattern.match, match, d, semantic))
                {
                    classSuffixCode = pattern.code;
                    break;
                }
            }
            if (classSuffixCode.length)
            {
                code.customIndent = newCustomIndent;
                code.writeln(data.options.indent, classSuffixCode);
                code.startLine();
                code.customIndent = origCustomIndent;
            }
        }

        parseTreeToDCode(code, data, d.tree.childs[1].childs[2], condition2, currentScope);
        code.customIndent = newCustomIndent;
        writeComments(code, data, d.tree.location.end);
        writeComments(code, data,
                data.sourceTokenManager.collectTokensUntilLineEnd(d.tree.location.end, d.condition));
    }
    else if (d.type == DeclarationType.macro_)
    {
        MacroDeclaration macroDeclaration = cast(MacroDeclaration) d;
        if (macroDeclaration.definition.isValid)
        {
            if (data.options.addDeclComments)
                code.writeln("// ", macroDeclaration.definition.name);
        }
        writeComments(code, data, macroDeclaration.location.end);

        bool[string] done;
        foreach (instance; macroDeclaration.instances)
        {
            Tree parent = getRealParent(instance.macroTrees[0], semantic);
            if (data.options.addDeclComments)
                code.writeln("// instance ", (!parent.isValid) ? "null" : parent.name,
                        " ", recreateMergedName(instance.macroTrees[0]), " ", locationStr(LocationX(LocationN.init,
                            instance.locationContextInfo.locationContext)) /*, " ", instance.locationContextInfo.condition.toString*/ );
            if (instance.usedName.length == 0)
                continue;
            if (instance.usedName !in done)
            {
                if (macroDeclaration.definition.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
                {
                    if (instance.macroTranslation.among(MacroTranslation.enumValue,
                            MacroTranslation.alias_))
                    {
                        code.write("template ", instance.usedName, "(");
                        code.writeln("params...) if (params.length == ",
                                instance.paramNames.length, ")");
                        code.writeln("{").incIndent;
                        foreach (i, p; instance.paramNames)
                        {
                            if (
                                instance.params[p.realName].instances[0].macroTranslation
                                    == MacroTranslation.alias_)
                                code.writeln("alias ", p.usedName, " = params[", i, "];");
                            else
                                code.writeln("enum ", p.usedName, " = params[", i, "];");
                        }
                        code.customIndent = origCustomIndent;
                        code.writeln(instance.macroTranslation == MacroTranslation.enumValue ? "enum " : "alias ",
                                    instance.usedName, " =",
                                    instance.instanceCode[0 .. instance.realCodeStart],
                                    instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd], ";",
                                    instance.instanceCode[instance.realCodeEnd
                                        .. $].withoutTrailingWhitespace);
                        code.customIndent = newCustomIndent;
                        code.decIndent.writeln("}");
                    }
                    else if (instance.macroTranslation == MacroTranslation.mixin_)
                    {
                        code.write("extern(D) ");
                        code.write("alias ", instance.usedName, " = function string(");
                        foreach (i, p; instance.paramNames)
                        {
                            if (i)
                                code.write(", ");
                            code.write("string ", p.usedName);
                        }
                        code.writeln(")");
                        code.writeln("{").incIndent;
                        code.customIndent = origCustomIndent;
                        code.write("return", instance.instanceCode[0 .. instance.realCodeStart]);
                        if (!code.data[$ - 1].inCharSet!" \t\r\n")
                            code.write(" ");
                        code.writeln("mixin(interpolateMixin(q{",
                                instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd],
                                "}));",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                        code.customIndent = newCustomIndent;
                        code.decIndent.writeln("};");
                    }
                }
                else
                {
                    code.customIndent = origCustomIndent;
                    string innerCode = instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd];
                    if (instance.macroTranslation == MacroTranslation.enumValue)
                        code.writeln("enum ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                innerCode, ";",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                    else if (instance.macroTranslation == MacroTranslation.alias_)
                        code.writeln("alias ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                innerCode, ";",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                    else if (instance.macroTranslation == MacroTranslation.mixin_)
                    {
                        string codePrefix = "q{";
                        string codeSuffix = "}";
                        if (instance.mixinMacroHasInterpolation)
                        {
                            codePrefix = "mixin(interpolateMixin(" ~ codePrefix;
                            codeSuffix ~= "))";
                        }
                        if (instance.canForwardMacroMixin && innerCode.startsWith("$(") && innerCode.endsWith(")"))
                        {
                            codePrefix = "";
                            codeSuffix = "";
                            innerCode = innerCode[2 .. $ - 1];
                        }
                        code.writeln("enum ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                codePrefix, innerCode, codeSuffix,
                                ";",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                    }
                    code.customIndent = newCustomIndent;
                }
            }
            else if (data.options.addDeclComments)
                code.writeln("// see ", instance.usedName);
            done[instance.usedName] = true;
        }
    }
    else if (d.type == DeclarationType.comment)
    {
        writeComments(code, data, d.location.end);
    }
    else if (d.type == DeclarationType.namespace)
    {
    }
    else if (d.type == DeclarationType.namespaceBegin)
    {
        data.markDeclarationUsed(d);
        code.customIndent = origCustomIndent;
        foreach (c; d.declaratorTree.childs[0 .. 1])
        {
            parseTreeToDCode(code, data, c, condition2, currentScope);
        }
        skipToken(code, data, d.declaratorTree.childs[1]); // namespace
        code.write("extern(C++,");
        skipToken(code, data, d.declaratorTree.childs[2]); // Identifier
        code.write("\"", d.declaratorTree.childs[2].content, "\")");
        foreach (c; d.declaratorTree.childs[3 .. $ - 2])
        {
            parseTreeToDCode(code, data, c, condition2, currentScope);
        }
        code.customIndent = newCustomIndent;
    }
    else if (d.type == DeclarationType.namespaceEnd)
    {
        data.markDeclarationUsed(d);
        code.customIndent = origCustomIndent;
        parseTreeToDCode(code, data, d.tree, condition2, currentScope);
        code.customIndent = newCustomIndent;
    }
    else
    {
        code.customIndent = origCustomIndent;
        foreach (c; d.tree.childs)
        {
            parseTreeToDCode(code, data, c, condition2, currentScope);
        }
        code.customIndent = newCustomIndent;
        if (d.tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier")
            code.writeln(";");
    }
}

string qualifyName(string name, Declaration d, DWriterData data, Scope currentScope,
        immutable(Formula)* condition)
{
    auto semantic = data.semantic;
    immutable(Formula)* conditionInOneModule = semantic.logicSystem.false_;
    immutable(Formula)* conditionInMultipleModules = semantic.logicSystem.false_;
    if (auto inModules = name in data.modulesBySymbol)
        foreach (filename, fcondition; *inModules)
            if (filename in data.importGraphHere || filename == data.currentFilename.moduleName)
            {
                immutable(Formula)* condition2 = fcondition;
                if (auto inImportGraph = filename in data.importGraphHere)
                    condition2 = semantic.logicSystem.and(fcondition,
                            inImportGraph.condition);
                conditionInMultipleModules = semantic.logicSystem.or(conditionInMultipleModules,
                        semantic.logicSystem.and(conditionInOneModule, condition2));
                conditionInOneModule = semantic.logicSystem.or(conditionInOneModule, condition2);
            }

    Scope realScope = d.scope_;
    if (realScope !is null)
        if (auto childScope = d.tree in d.scope_.childScopeByTree)
        {
            foreach (e; childScope.extraParentScopes.entries)
            {
                if (e.data.type != ExtraScopeType.namespace)
                    continue;
                if (semantic.logicSystem.and(e.condition, condition).isFalse)
                    continue;
                enforce(semantic.logicSystem.and(e.condition.negated, condition).isFalse);
                realScope = e.data.scope_;
                break;
            }
        }

    Scope realScopeNoNamespace = realScope;
    while (realScopeNoNamespace !is null && realScopeNoNamespace.parentScope !is null && !realScopeNoNamespace.tree.isValid) // Skip over namespaces
        realScopeNoNamespace = realScopeNoNamespace.parentScope;

    bool hasConflictingName = false;
    if (realScopeNoNamespace !is null && realScopeNoNamespace.parentScope is null)
    {
        for (Scope s = currentScope; s !is null && s.parentScope !is null; s = s.parentScope)
        {
            auto x = name in s.symbols;
            if (x)
            {
                foreach (e2; (*x).entries)
                {
                    if (e2.data.type != DeclarationType.forwardScope && e2.data !is d
                            && s !is realScope)
                    {
                        hasConflictingName = true;
                    }
                }
            }
        }
    }

    auto inFileByDecl = d in data.fileByDecl;
    if (inFileByDecl
        && ((realScope !is null && realScope.parentScope is null) || d.type == DeclarationType.macro_)
        && data.currentMacroInstance !is null
        && data.currentMacroInstance.macroDeclaration !is null
        && data.currentMacroInstance.macroDeclaration.type == DeclarationType.macro_
        && data.currentMacroInstance.macroTranslation == MacroTranslation.mixin_)
        name = data.options.importedSymbol ~ "!q{" ~ inFileByDecl.moduleName ~ "}." ~ name;
    else if (inFileByDecl && data.fileByDecl[d] != data.currentFilename
            && (!conditionInMultipleModules.isFalse || name in data.importedPackagesGraphHere))
        name = inFileByDecl.moduleName ~ "." ~ name;
    else if (inFileByDecl && data.fileByDecl[d] != data.currentFilename
            && realScope !is null && !realScope.tree.isValid
            && d.declarationSet.scope_.parentScope !is null)
        name = inFileByDecl.moduleName ~ "." ~ name; // Namespace
    else if (hasConflictingName)
        name = "." ~ name;

    return name;
}

string declarationNameToCode(Declaration d, DWriterData data, Scope currentScope,
        immutable(Formula)* condition)
{
    auto semantic = data.semantic;
    if (d.type == DeclarationType.builtin)
    {
        return d.name;
    }
    string name = chooseDeclarationName(d, data);
    if (name.length == 0)
    {
        return "";
    }

    Scope realScope = d.scope_;
    if (auto childScope = d.tree in d.scope_.childScopeByTree)
    {
        foreach (e; childScope.extraParentScopes.entries)
        {
            if (e.data.type != ExtraScopeType.namespace)
                continue;
            if (semantic.logicSystem.and(e.condition, condition).isFalse)
                continue;
            enforce(semantic.logicSystem.and(e.condition.negated, condition).isFalse);
            realScope = e.data.scope_;
            break;
        }
    }

    Scope extraScope = realScope;
    while (extraScope !is null && extraScope.parentScope !is null && !extraScope.tree.isValid) // Skip over namespaces
        extraScope = extraScope.parentScope;
    if (extraScope !is null && !isParentScopeOf(extraScope, currentScope, true))
    {
        Tree wrapperDeclaration = findWrappingDeclaration(extraScope.tree, semantic);
        foreach (d2; semantic.extraInfo(wrapperDeclaration).declarations)
        {
            if (d2.type == DeclarationType.type && d2.scope_ is extraScope.parentScope)
            {
                name = declarationNameToCode(d2, data, currentScope, condition) ~ "." ~ name;
                return name;
            }
        }
    }

    name = qualifyName(name, d, data, currentScope, condition);

    return name;
}
