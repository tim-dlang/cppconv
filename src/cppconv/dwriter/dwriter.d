
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter.dwriter;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.dwriter.declarationcode;
import cppconv.dwriter.macrodeclaration;
import cppconv.dwriter.typecode;
import cppconv.dwriter.declarationselection;
import cppconv.dwriter.treecode;
import cppconv.dwriter.conditioncode;
import cppconv.filecache;
import cppconv.grammarcpp;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import cppconv.treematching;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.typecons;

alias nonterminalIDFor = ParserWrapper.nonterminalIDFor;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

alias matchTreePattern = TreePattern!(cppconv.grammarcpp, Tree).matchTreePattern;
alias matchTreePatternDebug = TreePattern!(cppconv.grammarcpp, Tree).matchTreePatternDebug;

struct ImportExample
{
    Declaration d1, d2;
    LocationX locAdded;
}

class ImportInfo
{
    immutable(Formula)* condition;
    bool outsideFunction;
    ImportExample[] examples;
}

struct NameData
{
    immutable(Formula)* condition;
    size_t numVariants;
}

struct DeclarationData
{
    string chosenName;
    ConditionMap!string structBaseclasses;
    immutable(Formula)* movedDeclDone;
    string[] extraAttributes;
    string templateParamCode;
    string functionPrototypeCode;
    bool isAbstractClass;
}

enum DTypeKind
{
    none,
    struct_,
    class_
}

struct ModulePattern
{
    DeclarationPattern match;
    string moduleName;
    string extraPrefix;
}

struct RenamePattern
{
    DeclarationPattern match;
    string rename;
}

struct DTypeKindPattern
{
    DeclarationPattern match;
    DTypeKind kind;
}

struct CodePattern
{
    DeclarationPattern match;
    string code;
}

struct ManglingPattern
{
    ConfigRegex module_;
    string mangling;
}

struct FileHeaderReplacement
{
    ConfigRegex module_;
    string[] lines;
    ConfigRegexMultiline expectedLines;
}

struct DeclarationOrderPattern
{
    DeclarationPattern match;
    long order;
}

struct DCodeOptions
{
    DeclarationPattern[] blacklist;
    bool addDeclComments;
    string indent = "    ";
    string configModule = "config";
    string helperModule = "cppconvhelpers";
    string importedSymbol = "imported";
    bool includeAllDecls;
    ConfigRegex includeDeclFilenamePatterns;
    bool builtinCppTypes;
    string[string] docComments;
    ModulePattern[] modulePatterns;
    RenamePattern[] typeRenames;
    DTypeKindPattern[] typeKinds;
    string[string] macroReplacements;
    string[string] versionReplacements;
    string[] arrayLikeTypes;
    DeclarationPattern[] abstractClasses;
    CodePattern[] classSuffixCode;
    ManglingPattern[] defaultMangling;
    FileHeaderReplacement[] fileHeaderReplacement;
    ConfigRegex allowParameterImplicitCastsFilenamePatterns;
    ConfigRegex transitiveConstFilenamePatterns;
    DeclarationOrderPattern[] declarationOrder;
}

class DWriterData
{
    LogicSystem logicSystem;
    LocationContextMap locationContextMap;
    Semantic semantic;
    DCodeOptions options;
    RealFilename[] inputFiles;
    bool[string] inputFilesSet;
    MergedFile*[RealFilename] mergedFileByName;
    string[immutable(Formula)*] mergedAliasMap;
    Declaration[] decls;
    immutable(Formula)*[Declaration] forwardDecls;
    Declaration[][DFilename] declsByFile;
    DFilename[Declaration] fileByDecl;
    DTypeKind[Tree] dTypeKindCache;
    bool[Declaration] blacklistedCache;
    bool[Declaration] declarationUsed;
    void markDeclarationUsed(Declaration d)
    {
        auto e = d in declarationUsed;
        if (e)
            *e = true;
    }

    SourceToken[][][DFilename] sourceTokensPrefix;
    ImportInfo[string][DFilename] importGraph;
    bool[string][DFilename] importedPackagesGraph;
    MacroDeclarationInstance[Tree] macroReplacement;
    ConditionMap!MacroDeclarationInstance[immutable(LocationContext)*] macroInstanceByLocation;
    LocationX[Tree] nextTreeStart;
    DeclarationData[Declaration] declarationDatas;
    DeclarationData* declarationData(Declaration d)
    {
        auto x = d in declarationDatas;
        if (x)
            return x;
        declarationDatas[d] = DeclarationData();
        return d in declarationDatas;
    }

    NameData[string][DFilename][Scope] nameDatas;
    Declaration currentDeclaration;
    Declaration currentClassDeclaration;
    string[string] paramNameMap;
    bool[string] usedPackages;
    string[DeclarationSet] functionChosenName;
    bool afterStringLiteral;

    DFilename currentFilename;
    ImportInfo[string] importGraphHere;
    bool[string] importedPackagesGraphHere;
    string[immutable(Formula)*] versionReplacementsOr;
    immutable(Formula)*[string][string] modulesBySymbol;
    MacroDeclarationInstance currentMacroInstance;

    Declaration[string[2]] dummyDeclarations;
    Declaration dummyDeclaration(string name, string moduleName)
    {
        string[2] key = [name, moduleName];
        if (key in dummyDeclarations)
            return dummyDeclarations[key];
        Declaration d = new Declaration;
        d.name = name;
        d.type = DeclarationType.dummy;
        d.location = LocationRangeX(LocationX(LocationN.init,
                locationContextMap.getLocationContext(immutable(LocationContext)(null,
                LocationN.init, LocationN.LocationDiff.init, "", moduleName))),
                LocationN.LocationDiff.init);
        d.condition = logicSystem.true_;
        dummyDeclarations[key] = d;
        return d;
    }

    SourceTokenManager sourceTokenManager;
}

string packageName(string name)
{
    foreach (i, char c; name)
        if (c == '.')
            return name[0 .. i];
    return name;
}

string withoutTrailingWhitespace(string s)
{
    while (s.length && s[$ - 1].inCharSet!" \t")
        s = s[0 .. $ - 1];
    return s;
}

string getDefaultMangling(DWriterData data, DFilename filename)
{
    foreach_reverse (manglingPattern; data.options.defaultMangling)
    {
        if (manglingPattern.module_.match(filename.moduleName))
            return manglingPattern.mangling;
    }
    return "D";
}

immutable dKeywords = [
    "abstract",
    "alias",
    "align",
    "asm",
    "assert",
    "auto",
    "body",
    "bool",
    "break",
    "byte",
    "case",
    "cast",
    "catch",
    "cdouble",
    "cent",
    "cfloat",
    "char",
    "class",
    "const",
    "continue",
    "creal",
    "dchar",
    "debug",
    "default",
    "delegate",
    "delete",
    "deprecated",
    "do",
    "double",
    "else",
    "enum",
    "export",
    "extern",
    "false",
    "final",
    "finally",
    "float",
    "for",
    "foreach",
    "foreach_reverse",
    "function",
    "goto",
    "idouble",
    "if",
    "ifloat",
    "immutable",
    "import",
    "in",
    "inout",
    "int",
    "interface",
    "invariant",
    "ireal",
    "is",
    "lazy",
    "long",
    "macro",
    "mixin",
    "module",
    "new",
    "nothrow",
    "null",
    "out",
    "override",
    "package",
    "pragma",
    "private",
    "protected",
    "public",
    "pure",
    "real",
    "ref",
    "return",
    "scope",
    "shared",
    "short",
    "static",
    "struct",
    "super",
    "switch",
    "synchronized",
    "template",
    "this",
    "throw",
    "true",
    "try",
    "typeid",
    "typeof",
    "ubyte",
    "ucent",
    "uint",
    "ulong",
    "union",
    "unittest",
    "ushort",
    "version",
    "void",
    "wchar",
    "while",
    "with",

    "init", // not a keyword, but has special meaning
];

string replaceKeywords(string identifier)
{
    if (identifier == "__func__")
        identifier = "__FUNCTION__";
    if ( /*data.options.builtinCppTypes && */ identifier == "ulong")
        identifier = "cpp_ulong";

    foreach (k; dKeywords)
        if (identifier == k)
        {
            identifier = identifier ~ "_";
            break;
        }

    return identifier.replace("$", "_");
}

string replaceModuleKeywords(string s)
{
    string[] components = s.split(".");

    foreach (ref component; components)
        component = replaceKeywords(component);
    return components.join(".");
}

string replaceTypeName(DWriterData data, Declaration d, Semantic semantic)
{
    foreach_reverse (ref rename; data.options.typeRenames)
    {
        DeclarationMatch match;
        if (!isDeclarationMatch(rename.match, match, d, semantic))
            continue;

        return translateResult(rename.match, match, rename.rename).replace("-", "_");
    }

    return d.name;
}

immutable(LocationContext)* hasMacroReplacement(DWriterData data,
        immutable(LocationContext)* locContext, ref string replacement)
{
    while (locContext !is null)
    {
        auto x = locContext.name in data.options.macroReplacements;
        if (x)
        {
            replacement = *x;
            return locContext;
        }
        if (locContext.name.length == 0)
            return null;
        locContext = locContext.prev;
    }
    return null;
}

bool isLiteralPositive(immutable(Formula)* condition)
{
    assert(condition.type != FormulaType.and);
    assert(condition.type != FormulaType.or);
    bool isBound = condition.type == FormulaType.greaterEq || condition.type == FormulaType.less;
    if (!isBound)
    {
        return (condition.data.number == 0) == ((condition.type & 1) == 0);
    }
    else
    {
        if (condition.type & 1)
            return condition.data.number >= 1;
        else
            return condition.data.number < 0;
    }
}

bool isTreeExpression(Tree tree, Semantic semantic)
{
    if (tree.nodeType == NodeType.merged)
    {
        if (tree.name.endsWith("Expression"))
            return true;
    }
    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        foreach (c; tree.childs)
            if (c.isValid && !isTreeExpression(c, semantic))
                return false;
        return true;
    }
    if (tree.nameOrContent.endsWith("Expression")
            || tree.nameOrContent.canFind("Literal") || tree.nameOrContent == "BracedInitList")
        return true;
    if (tree.nameOrContent == "InitializerClause")
        return true;

    size_t indexInParent;
    Tree parent = getRealParent(tree, semantic, &indexInParent);
    if (!parent.isValid)
        return false;

    if (tree.nameOrContent.among("NameIdentifier"))
    {
        if (parent.nonterminalID == nonterminalIDFor!"CastExpression")
            return indexInParent == 1;
        if (parent.nameOrContent == "PostfixExpression"
                && parent.childs[1].nameOrContent.among("->", "."))
            return indexInParent == 0;
        if (parent.name.endsWith("Expression")
                || parent.nonterminalID == nonterminalIDFor!"StringLiteralSequence"
                || parent.name.endsWith("Initializer")
                || parent.nonterminalID == nonterminalIDFor!"BracedInitList"
                || parent.nonterminalID == nonterminalIDFor!"InitializerClause"
                || parent.nonterminalID == nonterminalIDFor!"InitializerClauseDesignator"
                || parent.name.canFind("Statement"))
            return true;
    }

    return false;
}

bool isTreeGlobalReference(Tree tree, Semantic semantic)
{
    size_t indexInParent;
    Tree parent = getRealParent(tree, semantic, &indexInParent);
    if (!parent.isValid)
        return false;
    if (tree.nameOrContent == "InitializerClause")
        return isTreeGlobalReference(tree.childs[0], semantic);
    if (tree.nameOrContent == "PrimaryExpression" && tree.childs.length == 3
            && tree.childs[0].nameOrContent == "(")
        return isTreeGlobalReference(tree.childs[1], semantic);
    if (!tree.nameOrContent.among("NameIdentifier"))
        return false;
    if (!isTreeExpression(tree, semantic))
        return false;

    if (semantic.extraInfo(tree).referenced.entries.length == 0)
        return false;
    foreach (x; semantic.extraInfo(tree).referenced.entries)
        if (!x.data.scope_.isRootNamespaceScope)
            return false;

    return true;
}

bool isTreePossibleMixin(Tree tree, Semantic semantic)
{
    if (isTreeExpression(tree, semantic))
        return true;
    if (tree.nodeType == NodeType.token)
        return false;
    if (tree.nodeType == NodeType.merged && tree.nonterminalID == nonterminalIDFor!"TemplateArgument2")
        return true;
    if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);
        size_t numPossible;
        foreach (i, c; tree.childs)
            if (!mdata.conditions[i].isFalse)
            {
                numPossible++;
                if (!isTreePossibleMixin(c, semantic))
                    return false;
            }
        return numPossible == 1;
    }
    if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        foreach (c; tree.childs)
            if (!isTreePossibleMixin(c, semantic))
                return false;
        return true;
    }
    if (tree.name.endsWith("Statement"))
        return true;
    if (tree.nonterminalID == nonterminalIDFor!"TypeId")
        return true;
    if (tree.nonterminalID == nonterminalIDFor!"QualifiedId")
        return true;
    if (tree.nonterminalID.nonterminalIDAmong!("StaticAssertDeclarationX",
            "StaticAssertDeclaration"))
        return true;
    Tree parent = getRealParent(tree, semantic);
    if (parent.isValid && parent.nonterminalID == nonterminalIDFor!"ClassBody")
        return true;
    return false;
}

bool isTreePossibleMixin(Tree[] trees, Semantic semantic)
{
    if (trees.length == 0)
        return false;
    foreach (tree; trees)
        if (!isTreePossibleMixin(tree, semantic))
            return false;
    return true;
}

alias hasBreakStatement = iterateTreeConditions!hasBreakStatementImpl;
void hasBreakStatementImpl(Tree tree, immutable(Formula)* condition, Semantic semantic, DWriterData data,
        ref immutable(Formula)* outCondition, ref immutable(Formula)* outConditionHasSwitch)
{
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
            hasBreakStatement(c, condition, semantic, data, outCondition, outConditionHasSwitch);
    }
    else if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nameOrContent == "JumpStatement2"
            && tree.childs[0].nameOrContent.among("break", "goto"))
    {
        outCondition = semantic.logicSystem.or(outCondition, condition);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"IterationStatement")
    {
    }
    else if (tree.nameOrContent == "SwitchStatement")
    {
        outConditionHasSwitch = semantic.logicSystem.or(outConditionHasSwitch, condition);
    }
    else if (tree.name.endsWith("Statement") || tree.nonterminalID == nonterminalIDFor!"TryBlock")
    {
        foreach (c; tree.childs)
            hasBreakStatement(c, condition, semantic, data, outCondition, outConditionHasSwitch);
    }
}

alias isStatementEndUnreachable = iterateTreeConditions!isStatementEndUnreachableImpl;
void isStatementEndUnreachableImpl(Tree tree, immutable(Formula)* condition,
        Semantic semantic, DWriterData data, ref immutable(Formula)* outCondition)
{
    if (tree.nodeType == NodeType.array)
    {
        if (tree.childs.length)
            isStatementEndUnreachable(tree.childs[$ - 1], condition, semantic, data, outCondition);
    }
    else if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nonterminalID == nonterminalIDFor!"IterationStatement")
    {
        if (auto match = tree.matchTreePattern!q{
                IterationStatement(IterationStatementHead("for", "(", *, null, ";", *, ")"), *)
                | IterationStatement(IterationStatementHead("while", "(", Literal("1"), ")"), *)
            })
        {
            immutable(Formula)* hasBreak = semantic.logicSystem.false_;
            immutable(Formula)* hasSwitch = semantic.logicSystem.false_;
            hasBreakStatement(tree.childs[$ - 1], condition, semantic, data, hasBreak, hasSwitch);
            outCondition = semantic.logicSystem.or(outCondition, semantic.logicSystem.and(condition,
                    semantic.logicSystem.and(hasBreak.negated, hasSwitch)));
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"Statement")
    {
        isStatementEndUnreachable(tree.childs[$ - 1], condition, semantic, data, outCondition);
    }
}

bool isCompoundStatementInSwitch(Tree tree, Semantic semantic)
{
    auto p1 = semantic.extraInfo(tree).parent;
    if (!p1.isValid)
        return false;
    auto p2 = semantic.extraInfo(p1).parent;
    if (!p2.isValid)
        return false;
    return p2.nameOrContent == "SwitchStatement"
        && p1.nameOrContent == "Statement" && tree.nameOrContent == "CompoundStatement";
}

void buildTemplateParamCode(Tree tree, immutable(Formula)* condition,
        ref CodeWriter code, DWriterData data)
{
    bool needsComma;
    void visitTree(Tree tree)
    {
        if (data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data, tree.start);

        scope (success)
        {
            if (data.sourceTokenManager.tokensLeft.data.length && tree.location.context !is null)
            {
                auto endTokens = data.sourceTokenManager.collectTokens(tree.location.end);
                //assert(endTokens.length == 0, text(tree.name, " ", locationStr(tree.start), " ", locationStr(tree.end, true)));
                writeComments(code, data, endTokens);
            }
        }

        if (tree.nodeType == NodeType.token)
        {
            if (tree.content == ",")
            {
                skipToken(code, data, tree);
                if (needsComma)
                    code.write(",");
                needsComma = false;
            }
        }
        else if (tree.nodeType == NodeType.array)
        {
            foreach (c; tree.childs)
                visitTree(c);
        }
        else if (tree.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
        {
            visitTree(tree.childs[2]);
        }
        else if (tree.nonterminalID == nonterminalIDFor!"TypeParameter")
        {
            if (needsComma)
                code.write(", ");
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(code, data,
                        data.sourceTokenManager.collectTokens(tree.end), true, true);
            if (tree.hasChildWithName("name"))
            {
                code.write(tree.childByName("name").content);
            }
            needsComma = true;
        }
        else if (tree.nonterminalID == nonterminalIDFor!"ParameterDeclarationAbstract")
        {
            visitTree(tree.childs[0]);
        }
        else if (tree.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq")
        {
            visitTree(tree.childs[0]);
        }
        else if (tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier")
        {
            if (needsComma)
                code.write(", ");
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(code, data,
                        data.sourceTokenManager.collectTokens(tree.end), true, true);
            if (tree.hasChildWithName("name"))
                code.write(tree.childByName("name").content);
            needsComma = true;
        }
        else if (tree.nonterminalID == nonterminalIDFor!"ParameterDeclaration")
        {
            if (needsComma)
                code.write(", ");
            if (data.sourceTokenManager.tokensLeft.data.length > 0)
                writeComments(code, data,
                        data.sourceTokenManager.collectTokens(tree.end), true, true);
            if (tree.hasChildWithName("name"))
                code.write(tree.childByName("name").name);

            foreach (d; data.semantic.extraInfo(tree).declarations)
            {
                declarationToDCode(code, data, d, condition);
            }

            needsComma = true;
        }
    }

    visitTree(tree);
}

immutable(Formula)* compatibleReferencedType(QualType t1, QualType declType, Semantic semantic)
{
    if (t1.type is null)
        return semantic.logicSystem.true_;

    immutable(Formula)* r = semantic.logicSystem.true_;

    outer: foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, semantic.logicSystem.true_);

        auto type1 = chooseType(t1, ppVersion, true);
        auto type2 = chooseType(declType, ppVersion, true);

        if (type1.type is null || type2.type is null)
            continue;

        if (type1.kind == TypeKind.function_ && type2.kind != TypeKind.function_) // Constructor calls
        {
            continue;
        }

        if (type1.kind != type2.kind)
        {
            r = semantic.logicSystem.and(r, ppVersion.condition.negated);
            continue;
        }
        if (type1.kind == TypeKind.function_)
        {
            auto ftype1 = cast(FunctionType) type1.type;
            auto ftype2 = cast(FunctionType) type2.type;
            foreach (i, p1; ftype1.parameters)
            {
                if (p1.type is null)
                    continue;
                if (i >= ftype2.parameters.length)
                {
                    r = semantic.logicSystem.and(r, ppVersion.condition.negated);
                    continue outer;
                }
                auto p2 = ftype2.parameters[i];
                if (p1 != p2)
                {
                    r = semantic.logicSystem.and(r, semantic.logicSystem.and(ppVersion.condition,
                            compatibleReferencedType(p1, p2, semantic).negated).negated);
                }
            }
        }
        if (type1.kind.among(TypeKind.pointer, TypeKind.reference, TypeKind.array))
        {
            r = semantic.logicSystem.and(r, semantic.logicSystem.and(ppVersion.condition,
                    compatibleReferencedType(type1.allNext()[0], type2.allNext()[0], semantic)
                    .negated).negated);
        }
        if (type1.kind == TypeKind.record)
        {
            if (type1 != type2)
            {
                r = semantic.logicSystem.and(r, ppVersion.condition.negated);
            }
        }
    }

    return r;
}

Scope highestNonNamespaceScope(Scope s)
{
    Scope r;
    while (s !is null)
    {
        if (s.tree.isValid)
            r = s;
        s = s.parentScope;
    }
    return r;
}

bool hasCommonParentScope(Scope s1, Scope s2)
{
    s1 = highestNonNamespaceScope(s1);
    s2 = highestNonNamespaceScope(s2);
    return s1 !is null && s2 !is null && s1 is s2;
}

void findRealDecl(DeclarationSet ds, bool isTypedef, ref ConditionMap!Declaration realDecl,
        LocationRangeX currentLoc, immutable(Formula)* condition,
        DWriterData data, Scope currentScope)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    foreach (e; ds.entries)
    {
        if (e.data.type != DeclarationType.type)
            continue;
        if (((e.data.flags & DeclarationFlags.typedef_) != 0) != isTypedef)
            continue;
        if (e.data.flags & DeclarationFlags.templateSpecialization)
            continue;
        LocationRangeX loc2 = e.data.location;
        if (e.data.tree.isValid)
            loc2 = e.data.location;
        immutable(Formula)* newCondition = logicSystem.and(condition, e.condition);
        if (!hasCommonParentScope(currentScope, e.data.scope_))
        {
            auto conditionReachable = locationReachable(currentLoc, loc2, data);
            if (e.data.scope_.isRootNamespaceScope && e.data.type == DeclarationType.varOrFunc && (e.data.flags & DeclarationFlags.static_) == 0)
                conditionReachable = logicSystem.or(conditionReachable, realDecl.conditionAll is null ? logicSystem.true_ : realDecl.conditionAll.negated);
            if (conditionReachable.isFalse)
                continue;
            newCondition = logicSystem.and(newCondition, conditionReachable);
        }

        foreach (e2; e.data.realDeclaration.entries)
        {
            realDecl.addReplace(logicSystem.and(newCondition,
                    e2.data.condition), e2.data, logicSystem);
        }

        if (e.data in data.forwardDecls)
        {
            newCondition = logicSystem.and(newCondition, data.forwardDecls[e.data].negated);
        }
        if (e.data.realDeclaration.conditionAll !is null)
            newCondition = semantic.logicSystem.and(newCondition,
                    e.data.realDeclaration.conditionAll.negated);
        if (newCondition.isFalse)
            continue;
        realDecl.addReplace(newCondition, e.data, logicSystem);
    }
}

void findRealDecl(Tree tree, ref ConditionMap!Declaration realDecl,
        immutable(Formula)* condition, DWriterData data, bool allowType, Scope currentScope)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;
    immutable(Formula)* nonType = logicSystem.false_;
    foreach (x; semantic.extraInfo(tree).referenced.entries)
        foreach (e; x.data.entries)
        {
            if (e.data.type == DeclarationType.forwardScope)
                continue;
            if (e.data.flags & DeclarationFlags.templateSpecialization)
                continue;
            LocationRangeX loc2 = e.data.location;
            if (e.data.tree.isValid)
                loc2 = e.data.location;
            immutable(Formula)* newCondition = logicSystem.and(condition,
                    logicSystem.and(x.condition, e.condition));
            if (!hasCommonParentScope(currentScope, e.data.scope_))
            {
                auto conditionReachable = locationReachable(tree.location, loc2, data);
                if (e.data.scope_.isRootNamespaceScope && e.data.type == DeclarationType.varOrFunc && (e.data.flags & DeclarationFlags.static_) == 0)
                {
                    conditionReachable = logicSystem.or(conditionReachable, realDecl.conditionAll is null ? logicSystem.true_ : realDecl.conditionAll.negated);
                }
                if (conditionReachable.isFalse)
                    continue;
                newCondition = logicSystem.and(newCondition, conditionReachable);
            }
            newCondition = logicSystem.and(newCondition,
                    compatibleReferencedType(semantic.extraInfo(tree).type, e.data.type2, semantic));

            if (/*e.data.scope_ is semantic.rootScope && !e.data.declarationSet.outsideSymbolTable &&*/ (e.data.flags & DeclarationFlags.static_) != 0
                    && (e.data.flags & DeclarationFlags.inline) == 0)
            {
                string hereFilename = tree.start.context.rootFilename;
                string declFilename = e.data.location.context.rootFilename;
                if (declFilename != hereFilename)
                {
                    bool avail;
                    foreach (inst; data.mergedFileByName[RealFilename(declFilename)].instances)
                        if (inst.locationPrefix.rootFilename == hereFilename)
                            avail = true;
                    if (!avail)
                        continue;
                }
            }

            if (e.data.type == DeclarationType.type)
            {
                newCondition = logicSystem.and(newCondition, nonType.negated);
            }
            else
            {
                nonType = logicSystem.or(nonType, newCondition);
            }

            foreach (e2; e.data.realDeclaration.entries)
            {
                auto condition2 = logicSystem.and(newCondition, e2.data.condition);
                if (e2.data.declarationSet.outsideSymbolTable)
                    continue;
                realDecl.addReplace(logicSystem.and(newCondition,
                        e2.data.condition), e2.data, logicSystem);
            }

            if (e.data in data.forwardDecls)
            {
                newCondition = logicSystem.and(newCondition, data.forwardDecls[e.data].negated);
            }
            if (e.data.realDeclaration.conditionAll !is null)
                newCondition = semantic.logicSystem.and(newCondition,
                        e.data.realDeclaration.conditionAll.negated);
            if (!allowType && e.data.type == DeclarationType.type)
            {
                newCondition = logicSystem.false_;
            }
            if (newCondition.isFalse)
                continue;
            realDecl.addReplace(newCondition, e.data, logicSystem);
        }
}

LocationX locationBeforeUsedMacro(Tree tree, DWriterData data, bool force)
{
    LocationX loc = tree.start;
    if (force || tree.nodeType == NodeType.array || tree in data.macroReplacement
            || (tree.nodeType == NodeType.nonterminal && tree.nonterminalID == nonterminalIDFor!"InitializerClause") // special case in applyMacroInstances
            || tree.nodeType == NodeType.merged
            || tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        while (loc.context !is null && (data.sourceTokenManager.tokensContext is null
                || loc.context.contextDepth > data.sourceTokenManager.tokensContext.contextDepth)
                && loc.context.name.length)
            loc = loc.context.parentLocation.start;
    }
    return loc;
}

bool inParameterList(T)(T tree, DWriterData data)
{
    auto semantic = data.semantic;
    if (!tree.isValid)
        return false;
    size_t indexInParent;
    Tree parent = getRealParent(tree, semantic, &indexInParent);
    if (!parent.isValid)
        return false;
    if (parent.nonterminalID == nonterminalIDFor!"InitializerClause")
    {
        size_t indexInParent2;
        Tree parent2 = getRealParent(parent, semantic, &indexInParent2);
        if (parent2.isValid && parent2.nonterminalID == nonterminalIDFor!"PostfixExpression")
            return true;
        return false;
    }
    if (parent.nonterminalID == nonterminalIDFor!"ConditionalExpression" && indexInParent > 0)
        return inParameterList(parent, data);
    if (parent.nonterminalID == nonterminalIDFor!"PrimaryExpression" && parent.childs.length == 3 && indexInParent == 1)
        return inParameterList(parent, data);
    return false;
}

void calcNeedsCast(T)(ref immutable(Formula)* needsCastCondition, ref immutable(Formula)* needsCastStaticArrayCondition,
        DWriterData data, T tree, immutable(Formula)* condition,
        Scope currentScope, ConditionalCodeWrapper* wholeExpressionWrapper)
{
    auto semantic = data.semantic;
    size_t indexInParent;
    size_t indexInParent2;
    Tree parent = getRealParent(tree, semantic, &indexInParent);
    Tree parent2 = getRealParent(parent, semantic, &indexInParent2);
    Tree parent3 = getRealParent(parent2, semantic);

    needsCastCondition = semantic.logicSystem.false_;
    needsCastStaticArrayCondition = semantic.logicSystem.false_;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, condition);

        auto toType1 = chooseType(semantic.extraInfo2(tree).convertedType, ppVersion, true);
        auto fromType1 = chooseType(semantic.extraInfo(tree).type, ppVersion, true);

        if (toType1.type is null || fromType1.type is null)
            continue;

        if (toType1.kind == TypeKind.reference)
        {
            toType1 = (cast(ReferenceType) toType1.type).next.withExtraQualifiers(
                    toType1.qualifiers);
        }
        if (fromType1.kind == TypeKind.reference)
        {
            fromType1 = (cast(ReferenceType) fromType1.type).next.withExtraQualifiers(
                    fromType1.qualifiers);
        }

        auto toType = filterType(toType1, ppVersion.condition, semantic,
                FilterTypeFlags.removeTypedef);
        auto fromType = filterType(fromType1, ppVersion.condition, semantic,
                FilterTypeFlags.removeTypedef);

        //if (tree.name != "LiteralS")
        if (fromType.kind == TypeKind.array && toType.kind == TypeKind.pointer)
        {
            auto pointerToType = cast(PointerType) toType.type;
            if (parent.nonterminalID == nonterminalIDFor!"CastExpression")
            {
                auto castType = chooseType(semantic.extraInfo(parent).type, ppVersion, true);
                assert(castType.kind == TypeKind.pointer);
                pointerToType = cast(PointerType) castType.type;
            }
            auto next = chooseType(pointerToType.next, ppVersion, true);
            if (tree.name != "LiteralS" || next.kind != TypeKind.builtin
                    || (parent.name != "CastExpression"
                        && !next.name.among("char", "wchar", "char16", "char32"))
                    || (parent.nonterminalID == nonterminalIDFor!"CastExpression"
                        && !next.name.among("char", "wchar", "char16", "char32", "signed_char", "unsigned_char"))
                    || semantic.extraInfo2(tree).preventStringToPointer
                    || parent.name.among("AdditiveExpression"))
            {
                fromType = QualType(semantic.getPointerType((cast(ArrayType) fromType.type)
                        .next), fromType.qualifiers);
                if (!combination.prefixDone && wholeExpressionWrapper !is null)
                {
                    if (tree.nonterminalID == nonterminalIDFor!"LiteralS" && tree.childs[0].nonterminalID == nonterminalIDFor!"StringLiteralSequence"
                        && (tree.childs[0].childs[0].childs.length != 1 || tree.childs[0].childs[0].childs[0].nonterminalID != nonterminalIDFor!"StringLiteral2"))
                        wholeExpressionWrapper.add("(", ").ptr", ppVersion.condition);
                    else
                        wholeExpressionWrapper.add("", ".ptr", ppVersion.condition);
                }
            }
        }

        if (tree.nonterminalID == nonterminalIDFor!"LiteralS")
        {
            if (toType1.type !is null && toType1.kind == TypeKind.array)
            {
                auto atype = cast(ArrayType) toType1.type;
                if ((atype.declarator.isValid && !atype.declarator.childs[2].isValid)
                        || parent3.name != "InitDeclarator")
                {
                    ConditionMap!string codeType;
                    if (!combination.prefixDone && wholeExpressionWrapper !is null)
                        wholeExpressionWrapper.add("staticString!(" ~ typeToCode(atype.next, data, ppVersion.condition,
                                currentScope, tree.location, [], codeType) ~ ", ",
                                ")", ppVersion.condition);
                }
            }
        }

        if (fromType.kind == TypeKind.function_ && toType.kind == TypeKind.pointer)
        {
            fromType = QualType(semantic.getPointerType(fromType));
            if (!combination.prefixDone && wholeExpressionWrapper !is null)
                wholeExpressionWrapper.add("&", "", ppVersion.condition);
        }

        if (fromType.kind == TypeKind.builtin && toType.kind == TypeKind.builtin
                && toType.name == "bool" && fromType.name != "bool" && tree.name != "Literal")
        {
            if (!combination.prefixDone && wholeExpressionWrapper !is null)
                wholeExpressionWrapper.add("(", ") != 0", ppVersion.condition);
        }

        if (parent2.name != "BracedInitList" && fromType.kind == TypeKind.builtin
                && toType.kind == TypeKind.builtin && semantic.extraInfo2(tree)
                    .constantValue.conditionAll !is null && isInCorrectVersion(ppVersion,
                        semantic.extraInfo2(tree).constantValue.conditionAll))
            continue;

        bool allowImplicitCast = false;
        if (inParameterList(tree, data) && data.options.allowParameterImplicitCastsFilenamePatterns.match(tree.location.context.filename))
            allowImplicitCast = true;

        if (needsCast(toType, fromType, ppVersion, semantic, allowImplicitCast))
        {
            if (toType.kind == TypeKind.array && (cast(ArrayType) toType.type)
                    .declarator.isValid && !(cast(ArrayType) toType.type)
                    .declarator.childs[2].isValid)
            {
                needsCastStaticArrayCondition = semantic.logicSystem.or(needsCastStaticArrayCondition,
                        ppVersion.condition);
            }
            else
                needsCastCondition = semantic.logicSystem.or(needsCastCondition,
                        ppVersion.condition);
        }
    }
}

Declaration getDummyDeclaration(Tree tree, DWriterData data, Semantic semantic)
{
    if (tree.nameOrContent == "DeleteExpression" && tree.childs.length == 3)
    {
        return data.dummyDeclaration("cpp_delete", "core.stdcpp.new_");
    }
    if (tree.nameOrContent == "NewExpression" && !tree.childs[2].isValid)
    {
        return data.dummyDeclaration("cpp_new", "core.stdcpp.new_");
    }
    if (tree.nameOrContent == "NewExpression" && tree.childs[2].isValid)
    {
        return data.dummyDeclaration("emplace", "core.lifetime");
    }
    return null;
}

bool isRValueParameter(Tree c, DWriterData data)
{
    auto semantic = data.semantic;
    if (data.options.allowParameterImplicitCastsFilenamePatterns.match(c.location.context.filename))
        return false;
    if (c.name != "InitializerClause")
        return false;
    if (c.childs[0].name != "PostfixExpression")
        return false;
    if (semantic.extraInfo2(c.childs[0]).convertedType.kind != TypeKind.reference)
        return false;
    if (semantic.extraInfo(c.childs[0].childs[0]).type.kind == TypeKind.function_)
        if (!semantic.extraInfo(c.childs[0]).type.kind.among(TypeKind.reference, TypeKind.none))
            return true;
    if (!semantic.extraInfo(c.childs[0].childs[0])
            .type.kind.among(TypeKind.function_, TypeKind.none))
        return true;
    return false;
}

bool isPostfixExpressionWithRValueRefs(Tree tree, DWriterData data)
{
    Tree argsTree = tree.childs[2];
    bool simpleTree = true;
    bool anyRValueRef = false;
    if (argsTree.nodeType == NodeType.array)
    {
        foreach (c; argsTree.childs)
        {
            if (c.nodeType == NodeType.array)
                return false;
            if (c.nodeType == NodeType.token)
                continue;
            if ((c.nonterminalID == CONDITION_TREE_NONTERMINAL_ID || c.nodeType == NodeType.merged))
                return false;
            if (isRValueParameter(c, data))
                anyRValueRef = true;
        }
    }
    return anyRValueRef;
}

void writePostfixExpressionWithRValueRefs(ref CodeWriter code, ref CodeWriter code2,
        DWriterData data, Tree tree, immutable(Formula)* condition, Scope currentScope)
{
    parseTreeToDCode(code2, data, tree.childs[0], condition, currentScope);
    parseTreeToDCode(code2, data, tree.childs[1], condition, currentScope); // (

    foreach (c; tree.childs[2].childs)
    {
        if (c.nodeType == NodeType.token)
        {
            parseTreeToDCode(code2, data, c, condition, currentScope);
        }
        else
        {
            if (isRValueParameter(c, data))
            {
                string tmpName = getFreeName("tmp", data.currentFilename,
                        condition, data, currentScope);
                code.write("auto ", tmpName, " = ");
                if (data.sourceTokenManager.tokensLeft.data.length > 0)
                    writeComments(code2, data, c.start);
                parseTreeToDCode(code, data, c, condition, currentScope);
                code.write("; ");
                code2.write(tmpName);
            }
            else
            {
                parseTreeToDCode(code2, data, c, condition, currentScope);
            }
        }
    }

    parseTreeToDCode(code2, data, tree.childs[3], condition, currentScope); // )
}

DTypeKind getDTypeKind(Tree tree, DWriterData data)
{
    auto semantic = data.semantic;
    if (tree.nonterminalID == nonterminalIDFor!"ClassSpecifier"
            || (tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier"
                && tree.childs[0].nonterminalID == nonterminalIDFor!"ClassKey"))
    {
        string classKey;
        if (tree.nonterminalID == nonterminalIDFor!"ClassSpecifier")
            classKey = tree.childs[0].childs[0].childs[0].nameOrContent;
        else if (tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier")
            classKey = tree.childs[0].childs[0].content;
        else
            assert(false);

        if (classKey != "struct" && classKey != "class")
            return DTypeKind.none;

        if (tree in data.dTypeKindCache)
            return data.dTypeKindCache[tree];

        data.dTypeKindCache[tree] = DTypeKind.none; // Prevent endless recursion

        DTypeKind r = DTypeKind.none;

        bool foundClassHint;
        foreach (d; semantic.extraInfo(findWrappingDeclaration(tree, semantic)).declarations)
        {
            if (d.tree in d.scope_.childScopeByTree)
            {
                Scope s2 = d.scope_.childScopeByTree[d.tree];
                foreach (name2, symbols; s2.symbols)
                    foreach (d2; symbols.entries)
                    {
                        if (d2.data.flags & DeclarationFlags.virtual)
                            foundClassHint = true;
                        if (d2.data.flags & DeclarationFlags.override_)
                            foundClassHint = true;
                    }

                foreach (combination; iterateCombinations())
                {
                    IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                            semantic.logicSystem.true_, null, semantic.mergedTreeDatas);
                    /*Tree nameTree = ppVersion.chooseTree(tree.childs[0]);
                    Tree valueTree;
                    if (tree.childs[1].isValid)
                    {
                        valueTree = ppVersion.chooseTree(tree.childs[1]);
                        assert(valueTree.nonterminalID == nonterminalIDFor!"AttributeArgumentClause");
                        valueTree = ppVersion.chooseTree(valueTree.childs[1]);
                        while (valueTree.nodeType != NodeType.token && valueTree.childs.length == 1)
                            valueTree = ppVersion.chooseTree(valueTree.childs[0]);
                    }
                    if (nameTree.childs[0].content == "pragma_pack")
                    {
                        info.pack.add(ppVersion.condition, valueTree.content.to!ubyte,
                                semantic.logicSystem);
                    }*/

                    Appender!(RecordType[]) parents;
                    classParents(parents, d, ppVersion, semantic, false);
                    foreach (parent; parents.data)
                    {
                        foreach (d2; parent.declarationSet.entries)
                            if (getDTypeKind(d2.data.tree, data) == DTypeKind.class_)
                                foundClassHint = true;
                    }
                }
            }
        }
        if (foundClassHint)
            r = DTypeKind.class_;
        else
            r = DTypeKind.struct_;

        auto declarations = semantic.extraInfo(findWrappingDeclaration(tree,
                semantic)).declarations;
        foreach (ref pattern; data.options.typeKinds)
        {
            bool isMatch;
            bool isRedundant = true;
            foreach (d; declarations)
            {
                DeclarationMatch match;
                bool prevUsed = pattern.match.used;
                if (isDeclarationMatch(pattern.match, match, d, semantic))
                {
                    if (!prevUsed)
                        pattern.match.redundant = true;
                    isMatch = true;
                    if (r != pattern.kind)
                        isRedundant = false;
                    r = pattern.kind;
                }
            }
            if (isMatch && !isRedundant)
                pattern.match.redundant = false;
        }

        data.dTypeKindCache[tree] = r;

        return r;
    }
    return DTypeKind.none;
}

bool isStruct(Tree tree, DWriterData data)
{
    return getDTypeKind(tree, data) == DTypeKind.struct_;
}

bool isClass(Tree tree, DWriterData data)
{
    return getDTypeKind(tree, data) == DTypeKind.class_;
}

struct ClassAttributes
{
    ConditionMap!ubyte pack;
    string classKey;
}

alias analyzeClassAttributes = iterateTreeConditions!analyzeClassAttributesImpl;
void analyzeClassAttributesImpl(Tree tree, immutable(Formula)* condition,
        Semantic semantic, ref ClassAttributes info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ClassSpecifier")
    {
        analyzeClassAttributes(tree.childs[0], condition, semantic, info);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ClassHead")
    {
        analyzeClassAttributes(tree.childs[0], condition, semantic, info);
        analyzeClassAttributes(tree.childs[1], condition, semantic, info);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ClassKey")
    {
        info.classKey = tree.childs[0].content;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"AttributeSpecifier")
    {
        analyzeClassAttributes(tree.childs[3], condition, semantic, info);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"Attribute")
    {
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, condition, null, semantic.mergedTreeDatas);
            Tree nameTree = ppVersion.chooseTree(tree.childs[0]);
            Tree valueTree;
            if (tree.childs[1].isValid)
            {
                valueTree = ppVersion.chooseTree(tree.childs[1]);
                assert(valueTree.nonterminalID == nonterminalIDFor!"AttributeArgumentClause");
                valueTree = ppVersion.chooseTree(valueTree.childs[1]);
                while (valueTree.nodeType != NodeType.token && valueTree.childs.length == 1)
                    valueTree = ppVersion.chooseTree(valueTree.childs[0]);
            }
            if (nameTree.childs[0].content == "pragma_pack")
            {
                info.pack.add(ppVersion.condition, valueTree.content.to!ubyte,
                        semantic.logicSystem);
            }
        }
    }
    else
    {
        foreach (c; tree.childs)
        {
            analyzeClassAttributes(c, condition, semantic, info);
        }
    }
}

bool hasEscapedNewline(Tree t)
{
    if (!t.isValid)
        return false;
    if (t.nodeType == NodeType.array)
    {
        foreach (c; t.childs)
            if (hasEscapedNewline(c))
                return true;
    }
    if (t.nodeType == NodeType.token && t.content.among("\\\n", "\\\r\n"))
        return true;
    return false;
}

void writeComments(ref CodeWriter code, DWriterData data, SourceToken[] tokens,
        bool onlyComments = false, bool skipExtraSpace = false, bool addDebugLocations = false)
{
    bool hasRealTokensBefore;
    size_t lastRealToken = size_t.max;
    bool ignoredToken(SourceToken t)
    {
        if (t.token.nodeType != NodeType.token && t.token.name.startsWith("Include"))
            return true;
        /*if (data.sourceTokenManager.currentMacroLocation !is null && t.token.location.context.filename == data.sourceTokenManager.currentMacroLocation.parentLocation.context.filename
            && t.token.location.start_ >= data.sourceTokenManager.currentMacroLocation.parentLocation.start_
            && t.token.location.end_ <= data.sourceTokenManager.currentMacroLocation.parentLocation.end_)*/
        {
            if (t.token.nodeType == NodeType.token && t.token.content.among("Q_OUTOFLINE_TEMPLATE",
                    "Q_DECL_CONSTEXPR", "Q_INLINE_TEMPLATE",
                    "Q_DECL_RELAXED_CONSTEXPR",
                    "QT_SIZEPOLICY_CONSTEXPR", "QT_POPCOUNT_CONSTEXPR", "QT_POPCOUNT_RELAXED_CONSTEXPR",
                    "Q_CONSTEXPR", "QT_BEGIN_NAMESPACE", "QT_END_NAMESPACE", "Q_INVOKABLE"))
                return true;
        }
        return false;
    }

    bool ignoredFuncMacro(SourceToken t)
    {
        if (data.sourceTokenManager.currentMacroLocation !is null
                && t.token.location.context.filename
                == data.sourceTokenManager.currentMacroLocation.parentLocation.context.filename
                && t.token.location.start_ >= data.sourceTokenManager.currentMacroLocation.parentLocation.start_
                && t.token.location.end_
                <= data.sourceTokenManager.currentMacroLocation.parentLocation.end_)
        {
            if (t.token.nodeType == NodeType.token
                    && t.token.content.among("Q_UINT64_C", "Q_INT64_C"))
                return true;
        }
        return false;
    }

    size_t posSemicolon = size_t.max;
    size_t numNonWhitespace;
    foreach (i, t; tokens)
    {
        if (t.isWhitespace)
            continue;
        if (t.token.nodeType == NodeType.token && t.token.content == ";")
            posSemicolon = i;
        numNonWhitespace++;
    }
    if (numNonWhitespace == 1 && posSemicolon != size_t.max)
        tokens = tokens[0 .. posSemicolon] ~ tokens[posSemicolon + 1 .. $];

    if (!onlyComments)
    {
        for (size_t i = 0; i < tokens.length; i++)
        {
            auto t = tokens[i];
            if (ignoredToken(t))
                continue;
            if (ignoredFuncMacro(t) && i + 1 < tokens.length)
            {
                size_t j = i + 1;
                while (j < tokens.length && tokens[j].isWhitespace)
                    j++;
                if (j < tokens.length && tokens[j].token.content == "(")
                {
                    j++;
                    size_t parens = 1;
                    while (j < tokens.length && parens)
                    {
                        if (tokens[j].token.content == "(")
                            parens++;
                        else if (tokens[j].token.content == ")")
                            parens--;
                        j++;
                    }
                    if (parens == 0)
                    {
                        i = j - 1;
                        continue;
                    }
                }
            }
            if (!t.isWhitespace)
            {
                lastRealToken = i;
            }
        }
    }
    Tree lastWSC;
    void writeTree(Tree t)
    {
        if (!t.isValid)
            return;
        if (lastWSC.isValid)
        {
            auto tmp = lastWSC;
            lastWSC = Tree.init;
            writeTree(tmp);
        }
        if (t.nodeType == NodeType.token)
            code.write(t.content);
        foreach (i, c; t.childs)
        {
            if (!c.isValid)
                continue;
            if (c.nodeType == NodeType.array && c.childs.length == 0)
                continue;
            if (lastWSC.isValid)
            {
                auto tmp = lastWSC;
                lastWSC = Tree.init;
                writeTree(tmp);
            }
            if (t.nodeType == NodeType.nonterminal
                    && t.childNonterminalName(i) == "WSC" && !hasEscapedNewline(c))
                lastWSC = c;
            else
                writeTree(c);
        }
    }

    static CodeWriter* lastIgnoredTokenWriter;
    static size_t lastIgnoredTokenPos;
    for (size_t i = 0; i < tokens.length; i++)
    {
        auto t = tokens[i];
        if (ignoredToken(t))
        {
            lastIgnoredTokenWriter = &code;
            lastIgnoredTokenPos = code.data.length;
            continue;
        }
        if (ignoredFuncMacro(t) && i + 1 < tokens.length)
        {
            size_t j = i + 1;
            while (j < tokens.length && tokens[j].isWhitespace)
                j++;
            if (j < tokens.length && tokens[j].token.content == "(")
            {
                j++;
                size_t parens = 1;
                while (j < tokens.length && parens)
                {
                    if (tokens[j].token.content == "(")
                        parens++;
                    else if (tokens[j].token.content == ")")
                        parens--;
                    j++;
                }
                if (parens == 0)
                {
                    lastIgnoredTokenWriter = &code;
                    lastIgnoredTokenPos = code.data.length;
                    foreach (t2; tokens[i .. j])
                    {
                        if (t2.isWhitespace)
                            code.write(t2.token.content);
                    }
                    i = j - 1;
                    continue;
                }
            }
        }
        bool afterIgnored = lastIgnoredTokenWriter is &code
            && lastIgnoredTokenPos == code.data.length;
        lastIgnoredTokenWriter = null;
        if (onlyComments && !t.isWhitespace)
            continue;
        if (t.isWhitespace && (skipExtraSpace || afterIgnored) && t.token.content.startsWith(" "))
            continue;
        if (t.isWhitespace && (skipExtraSpace || afterIgnored)
                && t.token.content.among("\r\n", "\n") && code.data.endsWith("\n"))
            continue;
        if (t.token.nodeType != NodeType.token)
        {
            writeTree(t.token.childs[0]);
        }
        if (!hasRealTokensBefore && !t.isWhitespace)
        {
            code.write("/+ ");
            hasRealTokensBefore = true;
        }

        string content = t.token.nameOrContent;
        if (t.token.nodeType == NodeType.token && t.isWhitespace)
        {
            if (content.among("\\\n", "\\\r\n"))
            {
                code.writeln();
                continue;
            }
            if (content.length && content[0].inCharSet!" \t\r\f")
            {
                if (i + 1 < tokens.length && tokens[i + 1].isWhitespace
                        && tokens[i + 1].token.content.among("\\\n", "\\\r\n"))
                    continue; // skip trailing whitespace
            }
        }

        if (t.token.nodeType != NodeType.token)
        {
            foreach (k, c; t.token.childs[1 .. $])
            {
                if (lastWSC.isValid)
                {
                    auto tmp = lastWSC;
                    lastWSC = Tree.init;
                    writeTree(tmp);
                }
                if (t.token.nodeType == NodeType.nonterminal
                        && t.token.childNonterminalName(k + 1) == "WSC")
                    lastWSC = c;
                else
                    writeTree(c);
            }
        }
        else
        {
            if (i + 1 == tokens.length)
            {
                if (t.token.nodeType == NodeType.token)
                    code.write(content /*.strip*/ );
            }
            else
            {
                if (t.token.nodeType == NodeType.token)
                    code.write(content);
            }
        }

        if (t.token.nodeType == NodeType.token && content.startsWith("//") && i + 1 == tokens
                .length)
            code.writeln();
        if (i == lastRealToken)
        {
            code.write(" +/");
            hasRealTokensBefore = false;
        }
        if (t.token.nodeType != NodeType.token)
        {
            if (lastWSC.isValid)
            {
                auto tmp = lastWSC;
                lastWSC = Tree.init;
                writeTree(tmp);
            }
            code.writeln();
        }
    }
    assert(!hasRealTokensBefore);
}

void writeComments(ref CodeWriter code, DWriterData data, LocationX loc, bool onlyComments = false)
{
    auto oldLocDone = data.sourceTokenManager.locDone;
    SourceToken[] tokens = data.sourceTokenManager.collectTokens(loc, false);
    writeComments(code, data, tokens, onlyComments, false, false);
    if (tokens.length)
        writeComments(code, data, data.sourceTokenManager.collectTokensUntilLineEnd(loc,
                tokens[$ - 1].condition, true), onlyComments);
}

void skipToken(ref CodeWriter code, DWriterData data, Tree tree,
        bool allowNonTerminal = false, bool removeWhitespace = false)
in (allowNonTerminal || tree.nodeType == NodeType.token, text(tree.name, " ", tree))
{
    if (data.sourceTokenManager.tokensLeft.data.length)
    {
        SourceToken[] tokens = data.sourceTokenManager.collectTokens(tree.start, false);
        bool removeWhitespaceLater;
        if (removeWhitespace)
        {
            removeWhitespaceLater = !code.inLine || tokens.length == 0;
            foreach (ref t; tokens)
            {
                if (t.isWhitespace && (t.token.content.startsWith("\n")
                        || t.token.content.startsWith("\r")))
                    removeWhitespaceLater = true;
                else if (t.isWhitespace && (t.token.content.startsWith(" ")
                        || t.token.content.startsWith("\t")))
                {
                }
                else
                    removeWhitespaceLater = false;
            }

            if (!removeWhitespaceLater)
            {
                while (tokens.length && tokens[$ - 1].isWhitespace
                        && (tokens[$ - 1].token.content.startsWith(" ")
                            || tokens[$ - 1].token.content.startsWith("\t")))
                    tokens = tokens[0 .. $ - 1];
            }
        }
        writeComments(code, data, tokens);
        auto removedTokens = data.sourceTokenManager.collectTokens(tree.end);

        if (removeWhitespace && removeWhitespaceLater && removedTokens.length)
        {
            tokens = data.sourceTokenManager.collectTokensUntilLineEnd(tree.end,
                    removedTokens[$ - 1].condition, 2);
            while (tokens.length && tokens[0].isWhitespace
                    && (tokens[0].token.content.startsWith(" ")
                        || tokens[0].token.content.startsWith("\t") /* || tokens[0].token.content.among("\n", "\r\n")*/ ))
                tokens = tokens[1 .. $];
            writeComments(code, data, tokens);
        }
    }
}

bool isExtraScopeOf(Scope p, Scope c)
{
    if (c is null)
        return false;
    if (p is c)
        return true;
    foreach (e; c.extraParentScopes.entries)
        if (isExtraScopeOf(p, e.data.scope_))
            return true;
    return false;
}

bool isParentScopeOf(Scope p, Scope c, bool followExtraScopes)
{
    if (c is null)
        return false;
    if (p is c)
        return true;
    if (isParentScopeOf(p, c.parentScope, followExtraScopes))
        return true;
    if (followExtraScopes)
    {
        foreach (e; c.extraParentScopes.entries)
            if (isExtraScopeOf(p, e.data.scope_))
                return true;
    }
    return false;
}

immutable(Formula)* typeIsClass(QualType type, DWriterData data)
{
    auto semantic = data.semantic;
    immutable(Formula)* r = semantic.logicSystem.false_;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination,
                semantic.logicSystem, semantic.logicSystem.true_);
        QualType t = chooseType(type, ppVersion, true);
        if (t.kind != TypeKind.record)
            continue;
        RecordType recordType = cast(RecordType) t.type;

        foreach (e; recordType.declarationSet.entries)
        {
            if (e.data.type != DeclarationType.type)
                continue;
            if ((e.data.flags & DeclarationFlags.typedef_) != 0)
                continue;
            if (!isClass(e.data.tree, data))
                continue;
            r = semantic.logicSystem.or(r,
                    semantic.logicSystem.and(ppVersion.condition, e.condition));
        }
    }
    return r;
}

immutable(Formula)* locationReachable(LocationRangeX loc1, LocationRangeX loc2, DWriterData data)
{
    auto semantic = data.semantic;
    string filename1 = loc1.start.context.rootFilename;
    string filename2 = loc2.start.context.rootFilename;
    immutable(Formula)* r = semantic.logicSystem.false_;
    immutable(Formula)* done = semantic.logicSystem.false_;
    foreach (tu, instances1; data.mergedFileByName[RealFilename(filename1)].tuToInstances)
    {
        MergedFileInstance[] instances2;
        if (RealFilename(filename2) in data.mergedFileByName
                && tu in data.mergedFileByName[RealFilename(filename2)].tuToInstances)
            instances2 = data.mergedFileByName[RealFilename(filename2)].tuToInstances[tu];
        foreach (ref inst1; instances1)
        {
            foreach (ref inst2; instances2)
            {
                if (inst1.locationPrefix is inst2.locationPrefix)
                {
                    if (loc2.start <= loc1.end)
                    {
                        r = semantic.logicSystem.or(r, semantic.logicSystem.and(inst1.instanceConditionUsed,
                                inst2.instanceConditionUsed));
                        if (r.isTrue)
                            return r;
                    }
                }
                else
                {
                    LocationX l1 = stackLocations(inst1.locationPrefix,
                            loc1.end, semantic.locationContextMap);
                    LocationX l2 = stackLocations(inst2.locationPrefix,
                            loc2.start, semantic.locationContextMap);
                    if (l2 <= l1)
                    {
                        r = semantic.logicSystem.or(r, semantic.logicSystem.and(inst1.instanceConditionUsed,
                                inst2.instanceConditionUsed));
                        if (r.isTrue)
                            return r;
                    }
                }
                done = semantic.logicSystem.or(done,
                        semantic.logicSystem.and(inst1.instanceConditionUsed,
                            inst2.instanceConditionUsed));
                if (done.isTrue)
                    break;
            }
        }
    }
    return r;
}

bool isRootNamespaceScope(Scope s)
{
    if (s is null)
        return false;
    if (s.parentScope is null)
        return true;
    if (!s.tree.isValid) // Namespace
        return isRootNamespaceScope(s.parentScope);
    return false;
}

string getFreeName(string name, DFilename filename,
        immutable(Formula)* condition, DWriterData data, Scope scope_ = null)
{
    if (scope_ !is null && scope_.parentScope is null)
        scope_ = null;

    size_t minNumVariants;
    if (scope_ is null || !scope_.tree.isValid || !scope_.tree.nonterminalID.nonterminalIDAmong!("ClassSpecifier", "EnumSpecifier"))
    {
        if (name in data.importedPackagesGraph.get(filename, null))
            minNumVariants = 1;
        void checkScope(Scope scope2)
        {
            foreach (e; scope2.extraParentScopes.entries)
                checkScope(e.data.scope_);
            auto w = ((scope2.parentScope is null) ? null : scope2) in data.nameDatas;
            if (!w)
                return;
            auto x = filename in *w;
            if (!x)
                return;
            auto y = name in *x;
            if (!y)
                return;
            if (1 > minNumVariants)
                minNumVariants = 1;
            if ((*y).numVariants > minNumVariants)
                minNumVariants = (*y).numVariants;
        }

        for (Scope scope2 = scope_ is null ? null : scope_.parentScope; scope2 !is null;
                scope2 = scope2.parentScope)
        {
            checkScope(scope2);
        }
    }

    auto w = scope_ in data.nameDatas;
    if (!w)
    {
        data.nameDatas[scope_] = null;
        w = scope_ in data.nameDatas;
    }
    auto x = filename in *w;
    if (!x)
    {
        (*w)[filename] = null;
        x = filename in *w;
    }
    auto y = name in *x;
    if (!y && minNumVariants == 0)
    {
        (*x)[name] = NameData(condition, 0);
        return name;
    }
    else
    {
        if (!y)
        {
            (*x)[name] = NameData(condition, 0);
            y = name in *x;
        }
        if (minNumVariants == 0 && data.logicSystem.and(condition, (*y).condition).isFalse)
        {
            (*y).condition = data.logicSystem.or(condition, (*y).condition);
            return name;
        }
        if ((*y).numVariants > minNumVariants)
        {
            string name2 = text(name, "__", (*y).numVariants);
            auto z = name2 in *x;
            if (data.logicSystem.and(condition, (*z).condition).isFalse)
            {
                (*z).condition = data.logicSystem.or(condition, (*z).condition);
                return name2;
            }
        }
        (*y).numVariants++;
        if ((*y).numVariants < minNumVariants)
            (*y).numVariants = minNumVariants;
        string name2 = text(name, "__", (*y).numVariants);
        (*x)[name2] = NameData(condition, 0);
        return name2;
    }
}

struct DFilename
{
    string moduleName;
    string extraPrefix;
    int opCmp(const DFilename rhs) const
    {
        if (extraPrefix < rhs.extraPrefix)
            return -1;
        if (extraPrefix > rhs.extraPrefix)
            return 1;
        if (moduleName < rhs.moduleName)
            return -1;
        if (moduleName > rhs.moduleName)
            return 1;
        return 0;
    }

    string toFilename() const
    {
        string r = moduleName.replace(".", "/") ~ ".d";
        if (extraPrefix.length)
            r = extraPrefix ~ "/" ~ r;
        return r;
    }
}

DFilename getDeclarationFilename(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    string name = fullyQualifiedName(semantic, d);
    if (d.name.length == 0 && d.type == DeclarationType.type
            && (d.flags & DeclarationFlags.typedef_) == 0)
    {
        auto d2 = getTypedefForDecl(d, data);
        if (d2 !is null)
        {
            name = fullyQualifiedName(semantic, d2);
        }
    }

    if (d.type == DeclarationType.dummy)
        return DFilename(d.location.context.filename);

    DFilename filename = getDeclarationFilename(d.location, data, name, d.flags);

    return filename;
}

DFilename getDeclarationFilename(LocationRangeX location, DWriterData data,
        string name, DeclarationFlags flags)
{
    bool inMacro;
    while (location.context !is null && location.context.name.length)
    {
        location = location.context.parentLocation;
        inMacro = true;
    }
    if (location.context is null || location.context.contextDepth < 1)
        return DFilename.init;
    return getDeclarationFilename(location.context.filename,
            location.start.line, inMacro, data, name, flags);
}

DFilename getDeclarationFilename(string filename, size_t startLine, bool inMacro,
        DWriterData data, string name, DeclarationFlags flags)
{
    string moduleName;
    string extraPrefix;

    foreach_reverse (ref modulePattern; data.options.modulePatterns)
    {
        DeclarationMatch match;
        if (!isDeclarationMatch(modulePattern.match, match, filename,
                startLine, inMacro, name, flags))
            continue;

        moduleName = replaceModuleKeywords(translateResult(modulePattern.match,
                match, modulePattern.moduleName).replace("-", "_").replace("/", "."));
        extraPrefix = translateResult(modulePattern.match, match, modulePattern.extraPrefix);
        break;
    }

    if (moduleName == "")
    {
        string packageName = "";
        foreach (i; 0 .. filename.length)
        {
            if (filename[i] == '/')
            {
                packageName = filename[0 .. i];
                break;
            }
        }
        moduleName = replaceModuleKeywords(filename.baseName.stripExtension.replace("-", "_").replace("/", "."));
        if (packageName.length)
            moduleName = replaceModuleKeywords(packageName.replace("-", "_").replace("/", ".")) ~ "." ~ moduleName;
    }

    if (moduleName in data.usedPackages)
        moduleName ~= "_";

    string fullPackageName;
    foreach_reverse (i; 0 .. moduleName.length)
    {
        if (moduleName[i] == '.')
        {
            fullPackageName = moduleName[0 .. i];
            break;
        }
    }

    if (fullPackageName.length)
        data.usedPackages[fullPackageName] = true;

    return DFilename(moduleName, extraPrefix);
}

ImportInfo[string] getNeededImportsLocal(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    ImportInfo[string] neededImportsLocal;

    Appender!(Tuple!(Declaration, immutable(Formula)*, bool, LocationX)[]) depsApp;
    foreach (d2, di2; getDeclDependencies(d, data))
    {
        if (!di2.outsideMixin)
            continue;
        if (d2.name.among("size_t", "ptrdiff_t"))
            continue;
        if (d2.name.among("__assert_fail", "assert"))
            continue;
        depsApp.put(tuple!(Declaration, immutable(Formula)*, bool,
                LocationX)(d2, di2.condition, di2.outsideFunction, di2.locAdded));
    }
    depsApp.data.sort!((a, b) => cmpDeclarationLoc(a[0], b[0], semantic));
    foreach (t2; depsApp.data)
    {
        auto d2 = t2[0];
        string filenameNoExt = getDeclarationFilename(d2, data).moduleName;
        if (d2.type != DeclarationType.dummy && d2 !in data.forwardDecls)
            continue;
        immutable(Formula)* condition = semantic.logicSystem.and(d.condition, d2.condition);
        if (d in data.forwardDecls)
            condition = semantic.logicSystem.and(condition, data.forwardDecls[d].negated);
        if (d2 in data.forwardDecls)
            condition = semantic.logicSystem.and(condition, data.forwardDecls[d2].negated);
        condition = semantic.logicSystem.and(condition, t2[1]);
        if (filenameNoExt != data.currentFilename.moduleName && !condition.isFalse)
        {
            ImportInfo importInfo;
            if (!t2[2] && (filenameNoExt !in data.importGraphHere
                    || !data.importGraphHere[filenameNoExt].outsideFunction))
            {
                if (filenameNoExt in neededImportsLocal)
                {
                    importInfo = neededImportsLocal[filenameNoExt];
                    importInfo.condition = semantic.logicSystem.or(importInfo.condition, condition);
                    importInfo.outsideFunction |= t2[2];
                }
                else
                {
                    importInfo = new ImportInfo;
                    neededImportsLocal[filenameNoExt] = importInfo;
                    importInfo.condition = condition;
                    importInfo.outsideFunction = t2[2];
                }
                if (importInfo.examples.length < 5)
                {
                    importInfo.examples ~= ImportExample(d, d2, t2[3]);
                }
            }
        }
    }
    return neededImportsLocal;
}

bool isConstExpression(Tree t, Semantic semantic, ref bool isType)
{
    size_t indexInParent;
    Tree parent = getRealParent(t, semantic, &indexInParent);
    if (t.nodeType == NodeType.nonterminal
            && t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        foreach (c; t.childs)
            if (!isConstExpression(c, semantic, isType))
                return false;
        return true;
    }
    if (t.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(t);

        if (!mdata.mergedCondition.isFalse)
            return false;

        foreach (i, condition; mdata.conditions)
        {
            if (!condition.isFalse)
            {
                if (!isConstExpression(t.childs[i], semantic, isType))
                    return false;
            }
        }

        return true;
    }
    if (t.nodeType == NodeType.nonterminal && t.nonterminalID == nonterminalIDFor!"TypeId")
    {
        isType = true;
        return true;
    }
    if (t.nodeType == NodeType.nonterminal && t.nonterminalID == nonterminalIDFor!"TypeKeyword")
    {
        isType = true;
        return true;
    }
    if (parent.isValid && parent.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq"
        && t.nodeType == NodeType.nonterminal && t.nonterminalID == nonterminalIDFor!"NameIdentifier")
    {
        isType = true;
        return true;
    }
    if (parent.isValid && parent.nonterminalID == nonterminalIDFor!"TypeId" && indexInParent == 0
        && t.nodeType == NodeType.nonterminal && t.nonterminalID == nonterminalIDFor!"NameIdentifier")
    {
        isType = true;
        return true;
    }
    if (!isTreeExpression(t, semantic))
        return false;
    if (t.name.endsWith("Literal"))
        return true;
    if (t.nonterminalID.nonterminalIDAmong!("StringLiteral2", "LiteralS", "LiteralSP"))
        return true;
    if (t.nonterminalID == nonterminalIDFor!"InitializerClause"
            && isConstExpression(t.childs[0], semantic, isType))
        return true;
    if (t.nameOrContent == "PrimaryExpression" && t.childs[0].nameOrContent == "("
            && isConstExpression(t.childs[1], semantic, isType))
        return true;
    if (t.nameOrContent == "UnaryExpression" && t.childs[0].nameOrContent.among("-",
            "+", "~", "!") && isConstExpression(t.childs[1], semantic, isType))
        return true;
    if (t.nonterminalID == nonterminalIDFor!"CastExpression"
            && isConstExpression(t.childs[1], semantic, isType))
        return true;
    if (t.nameOrContent == "UnaryExpression" && t.childs[0].nameOrContent.among("sizeof",
            "alignof") && t.childs[1].nameOrContent == "(")
        return true;
    if (t.nonterminalID.nonterminalIDAmong!("MultiplicativeExpression",
            "AdditiveExpression", "ShiftExpression", "RelationalExpression",
            "EqualityExpression", "AndExpression",
            "ExclusiveOrExpression", "InclusiveOrExpression",
            "LogicalAndExpression", "LogicalOrExpression")
            && isConstExpression(t.childs[0], semantic, isType)
            && isConstExpression(t.childs[2], semantic, isType))
        return true;
    if (t.nonterminalID == nonterminalIDFor!"ConditionalExpression"
            && isConstExpression(t.childs[0], semantic, isType)
            && isConstExpression(t.childs[2], semantic, isType)
            && isConstExpression(t.childs[4], semantic, isType))
        return true;
    return false;
}

bool skipDecl(Declaration d)
{
    if (d.type == DeclarationType.forwardScope)
        return true;
    if (d.flags & DeclarationFlags.enumerator)
        return true;
    if (d.name.among("size_t", "ptrdiff_t"))
        return true;
    return false;
}

bool isCommentLike(Declaration d, DWriterData data)
{
    if (d.type == DeclarationType.comment)
        return true;
    if (d.type == DeclarationType.macro_)
    {
        MacroDeclaration macroDeclaration = cast(MacroDeclaration) d;
        bool used;
        foreach (instance; macroDeclaration.instances)
        {
            if (instance.usedName.length)
                used = true;
        }
        if (!used)
            return true;
    }

    immutable(Formula)* skipForward = data.logicSystem.false_;
    if (d in data.forwardDecls)
        skipForward = data.forwardDecls[d];

    if (data.logicSystem.and(d.condition, skipForward.negated).isFalse)
        return true;

    return false;
}

void writeDecls(ref CodeWriter code, DWriterData data, Declaration[] decls,
        immutable(Formula)* condition)
{
    auto semantic = data.semantic;
    auto logicSystem = data.logicSystem;

    void writeIf(Declaration[] decls, immutable(Formula)* condition2)
    {
        auto condition3 = removeLocationInstanceConditions(condition2,
                semantic.logicSystem, data.mergedFileByName);
        condition3 = semantic.logicSystem.removeRedundant(condition3, condition);

        if (code.inLine)
            code.writeln();

        if (!isVersionOnlyCondition(condition3, data))
        {
            string conditionCode = conditionToDCode(condition3, data);
            if (conditionCode.startsWith("("))
                code.writeln("static if ", conditionCode, "");
            else
                code.writeln("static if (", conditionCode, ")");
        }
        else
        {
            versionConditionToDCode(code, condition3, data);
        }
        code.writeln("{");

        writeDecls(code, data, decls, condition2);

        if (code.inLine)
            code.writeln();
        code.writeln("}");
    }

    Appender!(SourceToken[]) commentTokens;
    void flushComments()
    {
        if (commentTokens.data.length == 0)
            return;

        if (code.inLine && !code.inIndent)
            code.writeln();
        writeComments(code, data, commentTokens.data, false, false, false  /*TODO: true*/ );

        commentTokens.shrinkTo(0);
    }

    void addCommentToken(SourceToken[] toks, size_t line = __LINE__)
    {
        if (toks.length)
        {
            commentTokens.put(toks);
        }
    }

    for (size_t i = 0; i < decls.length;)
    {
        if (skipDecl(decls[i]))
        {
            i++;
            continue;
        }

        if (decls[i].type == DeclarationType.namespaceBegin && decls[i].condition is condition)
        {
            size_t end = size_t.max;
            bool onlyComments = true;
            foreach (j; i + 1 .. decls.length)
            {
                if (decls[j].type == DeclarationType.namespaceEnd
                        && decls[j].condition is condition
                        && decls[j].tree is decls[i].declaratorTree.childs[$ - 1])
                {
                    end = j;
                    break;
                }
                if (!isCommentLike(decls[j], data) && !skipDecl(decls[j]))
                    onlyComments = false;
            }
            if (end != size_t.max && onlyComments)
            {
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[i]).tokensBefore);
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[i]).tokensInside);
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[i]).tokensAfter);
                if (onlyComments)
                {
                    foreach (d; decls[i + 1 .. end])
                    {
                        data.markDeclarationUsed(d);
                        addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensInside);
                    }
                }
                else if (end > i + 1)
                {
                    flushComments();
                    writeDecls(code, data, decls[i + 1 .. end], condition);
                }
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[end]).tokensBefore);
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[end]).tokensInside);
                addCommentToken(data.sourceTokenManager.declarationTokens(decls[end]).tokensAfter);
                i = end + 1;
                continue;
            }
        }

        if (isCommentLike(decls[i], data) && decls[i].condition is condition)
        {
            auto declarationTokens = data.sourceTokenManager.declarationTokens(decls[i]);
            if (declarationTokens.tokensInside.length == 1
                    && declarationTokens.tokensInside[0].token.nodeType != NodeType.token
                    && declarationTokens.tokensInside[0].token.name.among("PPIf",
                        "PPIfDef", "PPIfNDef"))
            {
                auto ppConditionalInfo = data.sourceTokenManager
                    .ppConditionalInfo[declarationTokens.tokensInside[0].token];
                size_t[] directivePos;
                directivePos.length = ppConditionalInfo.directives.length;
                directivePos[0] = i;
                {
                    size_t j = 1;
                    foreach (k; i + 1 .. decls.length)
                    {
                        if (isCommentLike(decls[k], data))
                        {
                            auto declarationTokens2 = data.sourceTokenManager.declarationTokens(
                                    decls[k]);
                            if (declarationTokens2.tokensInside.length == 1
                                    && declarationTokens2.tokensInside[0]
                                        .token is ppConditionalInfo.directives[j])
                            {
                                directivePos[j] = k;
                                j++;
                                if (j >= ppConditionalInfo.directives.length)
                                    break;
                            }
                        }
                    }
                    if (j < ppConditionalInfo.directives.length)
                        directivePos = null;
                }
                if (directivePos.length)
                {
                    bool needsDirectives = false;
                    bool onlyComments = true;
                    immutable(Formula)*[] conditions;
                    conditions.length = directivePos.length - 1;
                    foreach (j; 0 .. directivePos.length - 1)
                    {
                        if (directivePos[j] + 1 >= directivePos[j + 1])
                            needsDirectives = true;
                        immutable(Formula)* f = logicSystem.false_;
                        foreach (d; decls[directivePos[j] + 1 .. directivePos[j + 1]])
                        {
                            if (!isCommentLike(d, data) && !skipDecl(d))
                                onlyComments = false;
                            f = logicSystem.or(f, d.condition);
                        }
                        conditions[j] = f;
                        if (f is condition || f.isFalse)
                            needsDirectives = true;
                    }
                    if (onlyComments)
                    {
                        foreach (d; decls[i .. directivePos[$ - 1] + 1])
                        {
                            data.markDeclarationUsed(d);
                            addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensBefore);
                            addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensInside);
                            addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensAfter);
                        }
                    }
                    else if (needsDirectives)
                    {
                        foreach (j; 0 .. directivePos.length - 1)
                        {
                            data.markDeclarationUsed(decls[directivePos[j]]);
                            addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[j]])
                                    .tokensBefore);
                            addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[j]])
                                    .tokensInside);
                            addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[j]])
                                    .tokensAfter);

                            bool onlyComments2 = true;
                            foreach (d; decls[directivePos[j] + 1 .. directivePos[j + 1]])
                            {
                                if (!isCommentLike(d, data) && !skipDecl(d))
                                    onlyComments2 = false;
                            }
                            if (onlyComments2)
                            {
                                foreach (d; decls[directivePos[j] + 1 .. directivePos[j + 1]])
                                {
                                    data.markDeclarationUsed(d);
                                    addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensBefore);
                                    addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensInside);
                                    addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensAfter);
                                }
                            }
                            else
                            {
                                flushComments();
                                writeDecls(code, data, decls[directivePos[j] + 1 .. directivePos[j + 1]],
                                        condition);
                            }
                        }
                        data.markDeclarationUsed(decls[directivePos[$ - 1]]);
                        addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[$ - 1]])
                                .tokensBefore);
                        addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[$ - 1]])
                                .tokensInside);
                        addCommentToken(data.sourceTokenManager.declarationTokens(decls[directivePos[$ - 1]])
                                .tokensAfter);
                    }
                    else
                    {
                        foreach (j; 0 .. directivePos.length - 1)
                        {
                            flushComments();
                            writeIf(decls[directivePos[j] + 1 .. directivePos[j + 1]],
                                    conditions[j]);
                        }
                    }

                    i = directivePos[$ - 1] + 1;
                    continue;
                }
            }
        }

        size_t num = 1;
        immutable(Formula)* condition2 = decls[i].condition;
        if (condition2.isFalse)
        {
            while (i + num < decls.length)
            {
                if (skipDecl(decls[i + num]))
                {
                    num++;
                    continue;
                }
                if (decls[i + num].condition.isFalse)
                {
                    num++;
                }
                else
                    break;
            }
        }
        else
        {
            size_t numTmp = 1;
            while (i + numTmp < decls.length)
            {
                if (skipDecl(decls[i + numTmp]))
                {
                    numTmp++;
                    continue;
                }
                immutable(Formula)* condition3 = semantic.logicSystem.simpleBigOr(condition2,
                        decls[i + numTmp].condition);
                if (!semantic.logicSystem.and(condition3.negated, condition).isFalse)
                {
                    numTmp++;
                    if (!decls[i + numTmp - 1].condition.isFalse)
                    {
                        num = numTmp;
                        condition2 = condition3;
                    }
                }
                else
                    break;
            }
        }
        if (condition2 !is condition)
        {
            flushComments();
            writeIf(decls[i .. i + num], condition2);
        }
        else
        {
            foreach (d; decls[i .. i + num])
            {
                if (isCommentLike(d, data) || skipDecl(d))
                {
                    data.markDeclarationUsed(d);

                    if (d.type == DeclarationType.type
                            && d.tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier"
                            && d.tree.hasChildWithName("name"))
                    {
                        SourceToken[] tokensBefore = data.sourceTokenManager.declarationTokens(d).tokensBefore;
                        SourceToken[] tokensAfter0;
                        SourceToken[] tokensAfter = data.sourceTokenManager.declarationTokens(d).tokensAfter;

                        bool hasSemicolon;
                        foreach (j, t; tokensAfter)
                            if (t.token.content == ";")
                            {
                                tokensAfter0 = tokensAfter[0 .. j];
                                tokensAfter = tokensAfter[j + 1 .. $];
                                hasSemicolon = true;
                                break;
                            }
                        if (hasSemicolon && tokensAfter.length
                                && tokensAfter[0].token.content.among("\n", "\r\n"))
                        {
                            while (tokensBefore.length
                                    && tokensBefore[$ - 1].token.content[0].inCharSet!" \t\f")
                                tokensBefore = tokensBefore[0 .. $ - 1];
                            tokensAfter = tokensAfter[1 .. $];
                        }

                        addCommentToken(tokensBefore);
                        addCommentToken(tokensAfter0);
                        addCommentToken(tokensAfter);
                    }
                    else
                    {
                        addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensBefore);
                        addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensInside);
                        addCommentToken(data.sourceTokenManager.declarationTokens(d).tokensAfter);
                    }
                }
                else
                {
                    flushComments();
                    declarationToDCode2(code, data, d, condition2);
                }
            }
        }
        i += num;
    }
    flushComments();
}

bool writeImports(ref CodeWriter code, DWriterData data,
        ImportInfo[string] neededImports, immutable(Formula)* condition, bool allowLocal)
{
    auto semantic = data.semantic;
    bool haveIncludes = false;
    string origCustomIndent = code.customIndent;

    static struct ImportData
    {
        string conditionStr;
        string name;
        immutable(Formula)* condition;
        int opCmp(ref const ImportData rhs)
        {
            if (conditionStr != rhs.conditionStr)
                return (conditionStr < rhs.conditionStr) ? -1 : 1;
            if (name != rhs.name)
                return (name < rhs.name) ? -1 : 1;
            return 0;
        }
    }

    ImportData[] imports;
    foreach (name2, _; neededImports)
    {
        auto importInfo = neededImports[name2];
        if (!allowLocal && !importInfo.outsideFunction)
            continue;
        auto condition2 = removeLocationInstanceConditions(importInfo.condition,
                semantic.logicSystem, data.mergedFileByName);
        condition2 = semantic.logicSystem.removeRedundant(condition2, condition);
        imports ~= ImportData(condition2.isTrue ? "" : condition2.toString, name2, condition2);
    }
    sort(imports);

    foreach (i; 0 .. imports.length)
    {
        string name2 = imports[i].name;
        auto importInfo = neededImports[name2];
        auto condition2 = imports[i].condition;

        if (!haveIncludes)
        {
            string lastLineIndent;
            if (getLastLineIndent(code, lastLineIndent))
                code.writeln();
            string newCustomIndent = lastLineIndent.length ? lastLineIndent : code.customIndent;
            code.customIndent = newCustomIndent;
            if (allowLocal)
                code.customIndent = code.customIndent ~ data.options.indent;
        }

        bool closeBrace;
        if (!condition2.isTrue)
        {
            if (i && imports[i - 1].condition is condition2)
            {
                closeBrace = true;
                if (i + 1 < imports.length && condition2 is imports[i + 1].condition)
                    closeBrace = false;
            }
            else
            {
                if (!isVersionOnlyCondition(condition2, data))
                {
                    string conditionCode = conditionToDCode(condition2, data);
                    if (conditionCode.startsWith("("))
                        code.writeln("static if ", conditionCode, "");
                    else
                        code.writeln("static if (", conditionCode, ")");
                }
                else
                {
                    versionConditionToDCode(code, condition2, data);
                }

                if (i + 1 < imports.length && condition2 is imports[i + 1].condition)
                    code.writeln("{");
            }

            code.write(data.options.indent);
        }
        code.write("import ", name2, ";");
        if (data.options.addDeclComments)
        {
            foreach (e; importInfo.examples)
            {
                code.write(" // ", locationStr(e.locAdded), ": ", e.d1.name,
                        "(", locationStr(e.d1.location.start), ") -> ",
                        e.d2.name, "(", locationStr(e.d2.location.start), ")");
            }
        }
        code.writeln();
        if (closeBrace)
            code.writeln("}");
        haveIncludes = true;
    }
    if (!allowLocal && haveIncludes)
        code.writeln();
    code.customIndent = origCustomIndent;
    return haveIncludes;
}

void writeDCode(File outfile, FileCache fileCache, DWriterData data,
        Declaration[] decls, ImportInfo[string] neededImports)
{
    assert(data.sourceTokenManager.tokensLeft.data.length == 0);
    auto semantic = data.semantic;
    CodeWriter code;
    code.indentStr = data.options.indent;

    if (data.currentFilename in data.sourceTokensPrefix)
    {
        auto sourceTokensPrefix = data.sourceTokensPrefix[data.currentFilename];
        sourceTokensPrefix.sort!((a, b) {
            if (a.length == 0 || b.length == 0)
                return a.length < b.length;
            int c = cmpFilename(a[0].token.location.context.rootFilename,
                a[0].token.location.context.rootFilename);
            if (c != 0)
                return c < 0;
            return false;
        });
        foreach (k, tokens; sourceTokensPrefix)
        {
            size_t commentPrefix;

            // Remove comments at start, which where already in another .c/.h file for the same D module.
            if (k > 0)
                foreach (i, t; tokens)
                {
                    if (i >= sourceTokensPrefix[0].length
                            || sourceTokensPrefix[0][i].token.content != t.token.content)
                        break;
                    if (t.token.isToken && t.token.content.among("\n", "\r\n"))
                    {
                        commentPrefix = i + 1;
                    }
                }

            if (commentPrefix == 0 && tokens.length)
                foreach_reverse (fileHeaderReplacement; data.options.fileHeaderReplacement)
                {
                    if (fileHeaderReplacement.module_.match(data.currentFilename.moduleName))
                    {
                        string combinedComments;
                        foreach (i, t; tokens)
                        {
                            if (!t.token.isToken || !t.isWhitespace)
                                break;
                            combinedComments ~= t.token.content;
                            commentPrefix = i + 1;
                        }

                        string post;
                        if (!fileHeaderReplacement.expectedLines.match(combinedComments.replace("\r", ""), post))
                        {
                            writeln("File ", data.currentFilename.moduleName,
                                    " starts with unexpected comment:\n", combinedComments);
                            commentPrefix = 0;
                            break;
                        }
                        foreach (i, line; fileHeaderReplacement.lines)
                            code.write(line, i + 1 < fileHeaderReplacement.lines.length ? "\n" : "");
                        code.write(post);
                        break;
                    }
                }

            writeComments(code, data, tokens[commentPrefix .. $]);
        }
    }

    code.writeln("module ", data.currentFilename.moduleName, ";");

    string currentMangling = getDefaultMangling(data, data.currentFilename);
    if (currentMangling != "D")
        code.writeln("extern(", currentMangling, "):");
    code.writeln();

    neededImports[data.options.helperModule] = new ImportInfo;
    neededImports[data.options.helperModule].condition = semantic.logicSystem.true_;
    neededImports[data.options.helperModule].outsideFunction = true;
    neededImports[data.options.configModule] = new ImportInfo;
    neededImports[data.options.configModule].condition = semantic.logicSystem.true_;
    neededImports[data.options.configModule].outsideFunction = true;

    data.importGraphHere = null;
    data.importedPackagesGraphHere = null;
    if (data.currentFilename in data.importGraph)
        data.importGraphHere = data.importGraph[data.currentFilename];
    if (data.currentFilename in data.importedPackagesGraph)
        data.importedPackagesGraphHere = data.importedPackagesGraph[data.currentFilename];

    data.versionReplacementsOr = null;
    void addVersionOrCondition2(immutable(Formula)* condition)
    {
        if (condition.type != FormulaType.or)
            return;
        if (condition.subFormulas.length == 0)
            return;

        foreach (c; condition.subFormulas)
        {
            if (!isVersionOnlyCondition(c, data, false))
                return;
        }

        if (condition in data.versionReplacementsOr)
            return;

        string name;
        foreach (c; condition.subFormulas)
        {
            if (name.length)
                name ~= "Or";
            if (c in data.mergedAliasMap)
            {
                name ~= data.mergedAliasMap[c];
                continue;
            }
            else if (c.negated in data.mergedAliasMap)
            {
                name ~= "Not" ~ data.mergedAliasMap[c.negated];
                continue;
            }
            bool positive = isLiteralPositive(c);
            string name2 = c.data.name;
            if (name2.startsWith("defined("))
                name2 = name2["defined(".length .. $ - 1];
            string replaced = data.options.versionReplacements[name2];
            if (replaced.startsWith("!"))
            {
                replaced = replaced[1 .. $];
                positive = !positive;
            }
            if (!positive)
                name ~= "Not";
            name ~= replaced;
        }
        if (name == "OSXOriOSOrTVOSOrWatchOS")
            name = "Apple";
        foreach (c; condition.subFormulas)
        {
            if (c in data.mergedAliasMap)
            {
                code.writeln("version (", data.mergedAliasMap[c], ")");
                code.writeln(code.indentStr, "version = ", name, ";");
                continue;
            }
            else if (c.negated in data.mergedAliasMap)
            {
                code.writeln("version (", data.mergedAliasMap[c.negated], ") {} else");
                code.writeln(code.indentStr, "version = ", name, ";");
                continue;
            }
            bool positive = isLiteralPositive(c);
            string name2 = c.data.name;
            if (name2.startsWith("defined("))
                name2 = name2["defined(".length .. $ - 1];
            string replaced = data.options.versionReplacements[name2];
            if (replaced.startsWith("!"))
            {
                replaced = replaced[1 .. $];
                positive = !positive;
            }
            if (positive)
                code.writeln("version (", replaced, ")");
            else
                code.writeln("version (", replaced, ") {} else");
            code.writeln(code.indentStr, "version = ", name, ";");
        }
        code.writeln();
        data.versionReplacementsOr[condition] = name;
    }

    void addVersionOrCondition(immutable(Formula)* condition)
    {
        if (condition.type == FormulaType.and)
        {
            foreach (c; condition.subFormulas)
                addVersionOrCondition2(c);
            return;
        }
        addVersionOrCondition2(condition);
    }

    foreach (d; decls)
    {
        auto condition2 = removeLocationInstanceConditions(d.condition,
                semantic.logicSystem, data.mergedFileByName);
        if (d.type == DeclarationType.comment)
            continue;
        addVersionOrCondition(condition2);
    }
    foreach (name2; neededImports.sortedKeys)
    {
        auto importInfo = neededImports[name2];
        if (!importInfo.condition.isTrue)
        {
            auto condition2 = removeLocationInstanceConditions(importInfo.condition,
                    semantic.logicSystem, data.mergedFileByName);
            addVersionOrCondition(condition2);
        }
    }

    writeImports(code, data, neededImports, semantic.logicSystem.true_, false);

    writeDecls(code, data, decls, semantic.logicSystem.true_);

    outfile.writeln(code.data);
}

immutable(Formula)* usedConditionForFile(DWriterData data, RealFilename filename,
        bool onlyWithTree = false)
{
    immutable(Formula)* usedCondition;
    foreach (i, ref instance; data.mergedFileByName[filename].instances)
    {
        if (onlyWithTree && !instance.hasTree)
            continue;
        if (instance.instanceConditionUsed !is null)
        {
            if (usedCondition is null)
                usedCondition = data.logicSystem.false_;
            usedCondition = data.logicSystem.or(usedCondition, instance.instanceConditionUsed);
        }
    }
    return usedCondition;
}

void calcNextStart(DWriterData data, Tree tree, ref LocationX lastStart)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.array && tree.childs.length == 0)
        return;
    if (tree.nodeType == NodeType.merged || tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        data.nextTreeStart[tree] = lastStart;
    foreach_reverse (c; tree.childs)
    {
        calcNextStart(data, c, lastStart);
    }
    lastStart = tree.start;
}

bool isLineEndSourceToken(SourceToken t)
{
    if (t.token.nodeType == NodeType.token && t.token.content.among("\n", "\r\n"))
        return true;
    if (t.token.nodeType == NodeType.nonterminal && t.token.name.startsWith("PP"))
        return true;
    return false;
}

void writeAllDCode(string outputPath, bool outputIsDir, DCodeOptions options, Semantic mergedSemantic, FileCache fileCache,
        RealFilename[] inputFiles, MergedFile[] mergedFiles,
        string[immutable(Formula)*] mergedAliasMap, bool warnUnused)
{
    DWriterData data = new DWriterData;
    data.logicSystem = mergedSemantic.logicSystem;
    data.locationContextMap = mergedSemantic.locationContextMap;
    data.semantic = mergedSemantic;
    data.options = options;
    data.inputFiles = inputFiles;
    foreach (inputFile; inputFiles)
        data.inputFilesSet[inputFile.name] = true;

    data.sourceTokenManager = new SourceTokenManager;
    data.sourceTokenManager.logicSystem = mergedSemantic.logicSystem;
    data.sourceTokenManager.locationContextMap = mergedSemantic.locationContextMap;

    foreach (inputFile; inputFiles)
    {
        auto dfilename = getDeclarationFilename(inputFile.name, 0, false,
            data, "", DeclarationFlags.none);
        data.declsByFile[dfilename] = [];
    }

    foreach (ref mergedFile; mergedFiles)
    {
        getDeclarationFilename(mergedFile.filename.name, 0, false, data, "",
                DeclarationFlags.none);
        data.mergedFileByName[mergedFile.filename] = &mergedFile;
        size_t lastI;
        string lastTU;
        foreach (i, ref inst; mergedFile.instances)
        {
            string tu = inst.locationPrefix.rootFilename;
            size_t start = i;
            if (i && tu == lastTU)
            {
                mergedFile.tuToInstances[tu] = mergedFile.instances[lastI .. i + 1];
            }
            else
            {
                assert(tu !in mergedFile.tuToInstances);
                mergedFile.tuToInstances[tu] = mergedFile.instances[i .. i + 1];
                lastI = i;
                lastTU = tu;
            }
        }
    }
    data.sourceTokenManager.mergedFileByName = data.mergedFileByName;
    data.mergedAliasMap = mergedAliasMap;
    foreach (k, ref v; mergedAliasMap)
    {
        if (v in data.options.versionReplacements)
            v = data.options.versionReplacements[v];
    }

    foreach (filename, mergedFile; data.mergedFileByName)
    {
        foreach (t; mergedFile.mergedTrees)
        {
            LocationX lastStart;
            calcNextStart(data, t, lastStart);
        }
    }

    foreach (filename, mergedFile; data.mergedFileByName)
    {
        FileData fileData = fileCache.getFile(filename);
        if (fileData.notFound)
            continue;
        SourceToken[] sourceTokens;
        SourceToken[] sourceTokensMacros;
        LocConditions.Entry[] locEntries = mergedFile.locConditions.entries;
        processSource(data.sourceTokenManager, fileData.tree, sourceTokens,
                sourceTokensMacros, locEntries, null, true);
        size_t commentPrefix;
        foreach (i, t; sourceTokens)
        {
            if (!t.isWhitespace || !t.token.isToken)
                break;
            if (t.token.isToken && t.token.content.among("\n", "\r\n"))
            {
                if (i && sourceTokens[i - 1].token.content.among("\n", "\r\n"))
                    break;
                commentPrefix = i + 1;
            }
        }

        data.sourceTokensPrefix[getDeclarationFilename(filename.name, 0, false,
                    data, "", DeclarationFlags.none)] ~= sourceTokens[0 .. commentPrefix];

        sourceTokens = sourceTokens[commentPrefix .. $];
        while (sourceTokens.length)
        {
            if (sourceTokens[0].isIncludeGuard)
                sourceTokens = sourceTokens[1 .. $];
            else if (sourceTokens[0].token.nodeType == NodeType.nonterminal
                    && sourceTokens[0].token.nonterminalID == preprocNonterminalIDFor!"Include")
                sourceTokens = sourceTokens[1 .. $];
            else if (sourceTokens[0].token.nameOrContent.among("\n", "\r\n"))
                sourceTokens = sourceTokens[1 .. $];
            else if (sourceTokens.length >= 2 && sourceTokens[0].token.nameOrContent.among("QT_BEGIN_NAMESPACE")
                    && sourceTokens[1].token.nameOrContent.among("\n", "\r\n"))
                sourceTokens = sourceTokens[2 .. $];
            else
                break;
        }
        while (sourceTokens.length)
        {
            if (sourceTokens[$ - 1].isIncludeGuard)
                sourceTokens = sourceTokens[0 .. $ - 1];
            else if (sourceTokens[$ - 1].token.nodeType == NodeType.nonterminal
                    && sourceTokens[$ - 1].token.nonterminalID == preprocNonterminalIDFor!"Include")
                sourceTokens = sourceTokens[0 .. $ - 1];
            else if (sourceTokens.length >= 2 && sourceTokens[$ - 2].isLineEndSourceToken
                    && sourceTokens[$ - 1].token.nameOrContent.among("\n", "\r\n"))
                sourceTokens = sourceTokens[0 .. $ - 1];
            else if (sourceTokens.length >= 3 && sourceTokens[$ - 3].isLineEndSourceToken
                    && sourceTokens[$ - 2].token.nameOrContent.among("QT_END_NAMESPACE")
                    && sourceTokens[$ - 1].token.nameOrContent.among("\n", "\r\n"))
                sourceTokens = sourceTokens[0 .. $ - 2];
            else
                break;
        }

        data.sourceTokenManager.sourceTokens[filename] = sourceTokens;
        data.sourceTokenManager.sourceTokensMacros[filename] = sourceTokensMacros;
    }
    foreach (filename, mergedFile; data.mergedFileByName)
    {
        bool useDeclaration(Declaration d)
        {
            if (!isDeclarationBlacklisted(data, d) /* && !d.isRedundant*/ )
            {
                data.declarationUsed[d] = false;
                return true;
            }
            return false;
        }

        bool includeDeclsForFile2(string filename)
        {
            return includeDeclsForFile(data, filename);
        }

        matchDeclTokens(data.sourceTokenManager, mergedSemantic, mergedFile,
                &useDeclaration, &includeDeclsForFile2);
    }

    foreach (ref mergedFile; mergedFiles)
    {
        collectMacroInstances(data, mergedSemantic,
                mergedFile.locationContextInfoMap.getLocationContextInfo(null));
    }

    void restrictDeclCondition(Declaration d)
    {
        immutable(LocationContext)* locContext = d.location.context;
        while (locContext !is null && locContext.prev !is null)
            locContext = locContext.prev;
        if (locContext is null)
            return;

        immutable(Formula)* usedCondition = usedConditionForFile(data,
                RealFilename(locContext.filename));

        if (usedCondition !is null)
            d.condition = data.logicSystem.and(d.condition, usedCondition);
    }

    foreach (name, entries; mergedSemantic.rootScope.symbols)
    {
        foreach (e; entries.entries)
        {
            restrictDeclCondition(e.data);
        }
    }
    foreach (_, d; data.sourceTokenManager.macroDeclarations)
        restrictDeclCondition(d);

    selectDeclarations(data);

    void findQtTypeInfo(Tree t)
    {
        if (!t.isValid)
            return;
        if (t.nodeType == NodeType.array)
        {
            foreach (c; t.childs)
                findQtTypeInfo(c);
        }
        else if (t.nodeType == NodeType.nonterminal
                && t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            foreach (c; t.childs)
                findQtTypeInfo(c);
        }
        else if (t.nodeType == NodeType.token)
        {
        }
        else if (t.nonterminalID == nonterminalIDFor!"CppConvQtTypeInfoDecl")
        {
            if (t.childs[4].name != "NameIdentifier")
                return;
            if (t.childs[2].childs[0].childs.length != 1)
                return;
            auto c = t.childs[2].childs[0].childs[0];
            if (c.nonterminalID == nonterminalIDFor!"NameIdentifier")
            {
                foreach (e; mergedSemantic.extraInfo(c).referenced.entries)
                {
                    foreach (e2; e.data.entries)
                    {
                        if (e2.data.type != DeclarationType.type)
                            continue;
                        if (e2.data.flags & DeclarationFlags.forward)
                            continue;
                        data.declarationData(e2.data)
                            .extraAttributes.addOnce(t.childs[4].childs[0].content);

                        auto f = getDeclarationFilename(e2.data, data);

                        if (f !in data.importGraph)
                            data.importGraph[f] = null;

                        ImportInfo importInfo;
                        if ("qt.core.typeinfo" in data.importGraph[f])
                        {
                            importInfo = data.importGraph[f]["qt.core.typeinfo"];
                            importInfo.condition = mergedSemantic.logicSystem.or(importInfo.condition,
                                    e2.condition);
                            importInfo.outsideFunction |= true;
                        }
                        else
                        {
                            importInfo = new ImportInfo;
                            data.importGraph[f]["qt.core.typeinfo"] = importInfo;
                            importInfo.condition = e2.condition;
                            importInfo.outsideFunction = true;
                        }
                    }
                }
            }
        }
    }

    foreach (filename, mergedFile; data.mergedFileByName)
    {
        foreach (t; mergedFile.mergedTrees)
        {
            findQtTypeInfo(t);
        }
    }

    void findQtMetaTypeId(Tree t)
    {
        if (!t.isValid)
            return;
        if (t.nodeType == NodeType.array)
        {
            foreach (c; t.childs)
                findQtMetaTypeId(c);
        }
        else if (t.nodeType == NodeType.merged)
        {
            auto mdata = &mergedSemantic.mergedTreeData(t);
            foreach (i, c; t.childs)
                if (!mdata.conditions[i].isFalse)
                    findQtMetaTypeId(c);
        }
        else if (t.nodeType == NodeType.nonterminal
                && t.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
        {
            foreach (c; t.childs)
                findQtMetaTypeId(c);
        }
        else if (t.nonterminalID == nonterminalIDFor!"ClassSpecifier")
        {
            findQtMetaTypeId(t.childs[0]);
        }
        else if (t.nonterminalID == nonterminalIDFor!"ClassHead" && t.hasChildWithName("name"))
        {
            findQtMetaTypeId(t.childByName("name"));
        }
        else if (t.nonterminalID == nonterminalIDFor!"ClassHeadName")
        {
            findQtMetaTypeId(t.childs[$ - 1]);
        }
        else if (t.nonterminalID == nonterminalIDFor!"SimpleTemplateId")
        {
            findQtMetaTypeId(t.childs[2]);
        }
        else if (t.nonterminalID == nonterminalIDFor!"TypeId")
        {
            auto type = mergedSemantic.extraInfo(t).type;

            if (type.kind == TypeKind.record)
            {
                auto recordType = cast(RecordType) type.type;
                foreach (e2; recordType.declarationSet.entries)
                {
                    if (e2.data.type != DeclarationType.type)
                        continue;
                    if (e2.data.flags & DeclarationFlags.forward)
                        continue;
                    data.declarationData(e2.data)
                        .extraAttributes.addOnce("Q_DECLARE_METATYPE");

                    auto f = getDeclarationFilename(e2.data, data);

                    if (f !in data.importGraph)
                        data.importGraph[f] = null;

                    ImportInfo importInfo;
                    if ("qt.core.metatype" in data.importGraph[f])
                    {
                        importInfo = data.importGraph[f]["qt.core.metatype"];
                        importInfo.condition = mergedSemantic.logicSystem.or(importInfo.condition,
                                e2.condition);
                        importInfo.outsideFunction |= true;
                    }
                    else
                    {
                        importInfo = new ImportInfo;
                        data.importGraph[f]["qt.core.metatype"] = importInfo;
                        importInfo.condition = e2.condition;
                        importInfo.outsideFunction = true;
                    }
                }
            }
        }
    }
    if ("QMetaTypeId" in data.semantic.rootScope.symbols)
        foreach (e; data.semantic.rootScope.symbols["QMetaTypeId"].entries)
        {
            if (!(e.data.flags & DeclarationFlags.templateSpecialization))
                continue;
            findQtMetaTypeId(e.data.tree);
        }

    foreach (filename, decls; data.declsByFile)
    {
        foreach (d; decls)
        {
            data.fileByDecl[d] = filename;
            immutable(Formula)* skipForward = data.forwardDecls.get(d, data.logicSystem.false_);
            auto condition2 = mergedSemantic.logicSystem.and(d.condition, skipForward.negated);
            if (condition2.isFalse)
                continue;
            if (d.type == DeclarationType.type
                    && (d.flags & DeclarationFlags.typedef_) != 0
                    && isSelfTypedef(d, data))
                continue;
            string name = d.name;
            if (d.type != DeclarationType.macro_)
            {
                name = chooseDeclarationName(d, data);
            }
            if (name !in data.modulesBySymbol)
                data.modulesBySymbol[name] = null;
            if (filename.moduleName !in data.modulesBySymbol[name])
                data.modulesBySymbol[name][filename.moduleName] = condition2;
            else
                data.modulesBySymbol[name][filename.moduleName] = mergedSemantic.logicSystem.or(
                        data.modulesBySymbol[name][filename.moduleName], condition2);
        }
    }

    data.macroReplacement = null;
    foreach (ref mergedFile; mergedFiles)
    {
        bool[immutable(LocationContext)*] applyMacroInstancesDone;
        applyMacroInstances(data, mergedSemantic,
                mergedFile.locationContextInfoMap.getLocationContextInfo(null), applyMacroInstancesDone);
    }

    File outfile;
    if (!outputIsDir)
        outfile = File(outputPath, "w");
    foreach (name; data.declsByFile.sortedKeys)
    {
        if (outputIsDir)
        {
            string fullname = outputPath ~ "/" ~ name.toFilename;
            mkdirRecurse(dirName(fullname));
            outfile = File(fullname, "w");
        }
        else
        {
            outfile.writeln("// FILE: ", name.toFilename);
        }

        data.currentFilename = name;
        writeDCode(outfile, fileCache, data, data.declsByFile[name], data.importGraph[name]);

        if (outputIsDir)
            outfile.close();
    }

    foreach (d, used; data.declarationUsed)
    {
        if (d.type.among(DeclarationType.namespaceBegin, DeclarationType.namespaceEnd))
            continue;
        immutable(LocationContext)* locContext = d.location.context;
        if (locContext is null)
            continue;
        if (!includeDeclsForFile(data, locContext.filename))
            continue;
        if (warnUnused && !used)
            writeln("WARNING: Unused declaration ", d.name, " ", d.type, " ",
                    locationStr(d.location), " ", d.scope_.toString);
    }

    if (warnUnused)
        findUnusedPatterns(data.options);
}
