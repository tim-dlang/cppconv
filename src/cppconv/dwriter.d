
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.dwriter;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.dtypecode;
import cppconv.filecache;
import cppconv.grammarcpp;
import cppconv.logic;
import cppconv.macrodeclaration;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.sourcetokens;
import cppconv.treematching;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.typecons;

alias nonterminalIDFor = ParserWrapper.nonterminalIDFor;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

alias matchTreePattern = TreePattern!(cppconv.grammarcpp, Tree).matchTreePattern;
alias matchTreePatternDebug = TreePattern!(cppconv.grammarcpp, Tree).matchTreePatternDebug;

alias TypedefType = cppconv.cppsemantic.TypedefType;

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

void parseTreeToCodeTerminal(T)(ref CodeWriter code, string name)
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

struct ConditionalCodeWrapper
{
    ConditionMap!string conditionMapPrefix;
    ConditionMap!string conditionMapSuffix;
    DWriterData data;
    immutable(Formula)* firstCondition;
    immutable(Formula)* currentCondition;
    StringType currentStringType;
    bool forceExpression;

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

    void checkTree(Tree tree, bool allowNonArrayPPIf)
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
        if (tree.nodeType == NodeType.array)
        {
            foreach (c; tree.childs)
                checkTree(c, allowNonArrayPPIf);
        }
    }

    void checkTree(Tree[] trees, bool allowNonArrayPPIf)
    {
        foreach (c; trees)
            checkTree(c, allowNonArrayPPIf);
    }

    void changeCurrentCondition(ref CodeWriter code,
            immutable(Formula)* condition, StringType stringType)
    {
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
    {
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
            parseTreeToCodeTerminal!Tree(code, conditionMapPrefix.entries[0].data);
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
    {
        if (!alwaysUseMixin && conditionMapPrefix.entries.length == 1
                && conditionMapSuffix.entries.length == 1)
        {
            parseTreeToCodeTerminal!Tree(code, conditionMapSuffix.entries[0].data);
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
    }

    void writeTree(ref CodeWriter code, scope void delegate(Tree,
            immutable(Formula)*) F, Tree tree, immutable(Formula)* condition)
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
    {
        writeTree(code, F, tree, firstCondition);
    }

    void writeTree(ref CodeWriter code, scope void delegate(Tree,
            immutable(Formula)*) F, Tree[] trees)
    {
        foreach (c; trees)
            writeTree(code, F, c);
    }

    void writeString(ref CodeWriter code, string s)
    {
        changeCurrentCondition(code, firstCondition, StringType.string);
        code.write(s);
    }
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
        if (d.declarationSet in data.functionChosenName)
            return data.functionChosenName[d.declarationSet];
    }
    else
    {
        if (declarationData.chosenName.length)
            return declarationData.chosenName;
    }

    immutable(Formula)* skipForward = semantic.logicSystem.false_;
    if (d in data.forwardDecls)
        skipForward = data.forwardDecls[d];
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
        parseTreeToCodeTerminal!T(code, data.options.macroReplacements[commonMacro]);
        return;
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

enum TreeToCodeFlags
{
    none = 0,
    skipCasts = 1,
    inStatementExpression = 2,
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

        if (needsCast(toType, fromType, ppVersion, semantic))
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
            parseTreeToCodeTerminal!T(code, name);

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
                parseTreeToCodeTerminal!T(code, (instance.macroTranslation.among(MacroTranslation.mixin_,
                        MacroTranslation.builtin)) ? "(" : "!(");
                bool first = true;

                foreach (paramName; instance.paramNames)
                {
                    if (!first)
                        parseTreeToCodeTerminal!T(code, ",");
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
                parseTreeToCodeTerminal!T(code, ")");
            }
            parseTreeToCodeTerminal!T(code, macroSuffix);
            if (data.sourceTokenManager.tokensLeft.data.length && allowComments)
                data.sourceTokenManager.collectTokens(tree.location.end);
            if (instance.macroTranslation == MacroTranslation.mixin_
                    && (tree.name.endsWith("Statement") || (tree.nodeType == NodeType.merged && tree.nonterminalID == nonterminalIDFor!"Statement") || tree.nonterminalID == nonterminalIDFor!"StaticAssertDeclaration" || parent.nonterminalID == nonterminalIDFor!"ClassBody"))
                parseTreeToCodeTerminal!T(code, ";");
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
        parseTreeToCodeTerminal!T(code, macroReplacement);
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
        parseTreeToCodeTerminal!T(code, name);

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
            parseTreeToCodeTerminal!T(code, "{");
            parseTreeToCodeTerminal!T(code, "}");
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
            parseTreeToCodeTerminal!T(code, "assert(false)");
            parseTreeToCodeTerminal!T(code, ";");
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

        parseTreeToCodeTerminal!T(code, ";");
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
            parseTreeToCodeTerminal!T(code, replaceKeywords(tree.childs[1].content));
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
                "Condition", "AliasDeclaration"))
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
        parseTreeToCodeTerminal!T(code, "cast");
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
            parseTreeToCodeTerminal!T(code, ".sizeof");
        else
            parseTreeToCodeTerminal!T(code, ".alignof");
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

        parseTreeToCodeTerminal!T(code, ".");
        skipToken(code, data, tree.childs[4]);
        parseTreeToCodeTerminal!T(code, tree.childs[4].content);
        parseTreeToCodeTerminal!T(code, ".offsetof");
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
        parseTreeToCodeTerminal!T(code, tree.childs[0].content["__builtin_".length .. $]);
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
            parseTreeToCodeTerminal!T(code, "octal!" ~ t.replace("l", "L"));
        }
        else
        {
            value = value.replace("l", "L");
            if (value.endsWith("LL"))
                value = value[0 .. $ - 1];
            if (value.endsWith("i64"))
                value = value[0 .. $ - 3] ~ "L";
            parseTreeToCodeTerminal!T(code, value);
        }
        skipToken(code, data, tree.childs[0]);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CharLiteral")
    {
        string value = tree.childs[0].content;
        if (value.startsWith("L'"))
            parseTreeToCodeTerminal!T(code, value[1 .. $]);
        else
        {
            parseTreeToCodeTerminal!T(code, value);
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
            parseTreeToCodeTerminal!T(code, "wchar_literal!" ~ value[1 .. $]);
        else if (value.startsWith("u8\""))
            parseTreeToCodeTerminal!T(code, value[2 .. $]);
        else if (value.startsWith("u\""))
            parseTreeToCodeTerminal!T(code, value[1 .. $] ~ "w");
        else if (value.startsWith("U\""))
            parseTreeToCodeTerminal!T(code, value[1 .. $] ~ "d");
        else
            parseTreeToCodeTerminal!T(code, value);
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
            parseTreeToCodeTerminal!T(code, "()");
            parseTreeToCodeTerminal!T(code, "{");
            parseTreeToDCode(code, data, tree.childs[0], condition, currentScope, TreeToCodeFlags.inStatementExpression);
            parseTreeToCodeTerminal!T(code, ";");
            code.writeln();
            skipToken(code, data, tree.childs[1]);
            parseTreeToCodeTerminal!T(code, "return");
            writeComments(code, data, tree.childs[2].start);
            if (code.data.length && !code.data[$ - 1].inCharSet!" \t")
                code.write(" ");
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
            parseTreeToCodeTerminal!T(code, ";");
            code.writeln();
            parseTreeToCodeTerminal!T(code, "}");
            parseTreeToCodeTerminal!T(code, "()");
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
            parseTreeToCodeTerminal!T(code, "()");
            parseTreeToCodeTerminal!T(code, "{");
            parseTreeToCodeTerminal!T(code, "return ");
            foreach (c; tree.childs)
            {
                parseTreeToDCode(code, data, c, condition, currentScope);
            }
            parseTreeToCodeTerminal!T(code, ";");
            code.writeln();
            parseTreeToCodeTerminal!T(code, "}");
            parseTreeToCodeTerminal!T(code, "()");
        }
        else if (semantic.extraInfo2(tree).acessingBitField
                && tree.childs[1].childs[0].content != "=")
        {
            Tree accessor = tree.childs[0];
            assert(accessor.nonterminalID == nonterminalIDFor!"PostfixExpression");
            assert(accessor.childs.length == 3 || accessor.childs.length == 4);
            parseTreeToDCode(code, data, accessor.childs[0], condition, currentScope);
            parseTreeToCodeTerminal!T(code, ".fallbackAssignExpression!(q{");
            skipToken(code, data, accessor.childs[1]);
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "}, q{");
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "})(");
            parseTreeToDCode(code, data, tree.childs[2], condition, currentScope);
            parseTreeToCodeTerminal!T(code, ")");
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
            parseTreeToCodeTerminal!T(code, ".fallbackPostfixExpression!(q{");
            skipToken(code, data, accessor.childs[1]);
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "}, q{");
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "})(");
            parseTreeToCodeTerminal!T(code, ")");
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
            parseTreeToCodeTerminal!T(code, ".fallbackUnaryExpression!(q{");
            parseTreeToDCode(code, data, accessor.childs[$ - 1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "}, q{");
            parseTreeToCodeTerminal!T(code, tree.childs[0].content);
            parseTreeToCodeTerminal!T(code, "})(");
            parseTreeToCodeTerminal!T(code, ")");
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
        parseTreeToCodeTerminal!T(code, replaceKeywords(tree.childs[1].content));
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
            parseTreeToCodeTerminal!T(code, "/*(*/");
            skipToken(code, data, tree.childs[0]);
            parseTreeToDCode(code, data, tree.childs[1], condition, currentScope);
            parseTreeToCodeTerminal!T(code, "/*)*/");
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

                    if (declName != "")
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
            parseTreeToCodeTerminal!T(code, replaceKeywords(tree.childs[0].content));
        }
        else if (realId.entries.length == 1)
        {
            parseTreeToCodeTerminal!T(code, realId.entries[0].data);
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
    else if (tree.nonterminalID == nonterminalIDFor!"UsingDeclaration")
    {
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
                parseTreeToCodeTerminal!T(code, "is");
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
    else
    {
        foreach (c; tree.childs)
        {
            parseTreeToDCode(code, data, c, condition, currentScope);
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
    if (!(c.location.context.filename.startsWith("qt/orig/qt")
            || c.location.context.filename.startsWith("qt5/orig/qt")
            || c.location.context.filename.startsWith("qt6/orig/qt")))
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
            "FunctionAbstractDeclarator"))
    {
        info.functionDeclarator = t;
        findParams(t.childs[1], condition3, info, data, currentScope);
        findParams(t.childByName("virtSpec"), condition3, info, data, currentScope);
        //parseTreeToDCode(code, data, t.childs[1], condition2, currentScope);
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
    else if (t.nonterminalID == nonterminalIDFor!"ParametersAndQualifiers")
    {
        if (currentScope !is null && t in currentScope.childScopeByTree)
            currentScope = currentScope.childScopeByTree[t];

        findParams(t.childs[0], condition3, info, data, currentScope);

        if (t.childs[$ - 1].isValid)
        {
            if (t.childs[$ - 1].nodeType == NodeType.array)
                info.attributeTrees ~= t.childs[$ - 1].childs;
            else
                info.attributeTrees ~= t;
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
        parseTreeToCodeTerminal!Tree(code, ",");

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
                semantic.logicSystem, semantic.logicSystem.and(condition2, condition4));
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
    if (d in data.forwardDecls)
        skipForward = data.forwardDecls[d];

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
    if (currentScope !is null && d.tree in currentScope.childScopeByTree)
        currentScope = currentScope.childScopeByTree[d.tree];

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
        if (fname in data.options.docComments)
        {
            string lastLineIndentUnused;
            if (getLastLineIndent(code, lastLineIndentUnused))
                code.writeln();
            code.writeln("/// ", data.options.docComments[fname]);
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
                    "ParameterDeclaration", "Condition"))
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
                code.writeln(typeCode, " ", replaceKeywords(d.name), "() const");
                code.writeln("{").incIndent;
                code.writeln("return (", e.data.dataName, " >> ",
                        e.data.firstBit, ") & 0x",
                        toChars!16((ulong(1) << e.data.length) - 1), ";");
                code.decIndent.writeln("}");
                if (data.currentClassDeclaration !is null
                        && isClass(data.currentClassDeclaration.tree, data))
                    code.write("final ");
                code.writeln(typeCode, " ", replaceKeywords(d.name), "(", typeCode, " value)");
                code.writeln("{").incIndent;
                code.writeln(e.data.dataName, " = (", e.data.dataName,
                        " & ~0x", toChars!16(((ulong(1) << e.data.length) - 1) << e.data.firstBit),
                        ") | ((value & 0x", toChars!16((ulong(1) << e.data.length) - 1),
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
                "FunctionDefinitionGlobal") && (d.flags & DeclarationFlags.function_) == 0)
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

        bool closeCommentWholeDecl;
        if (d.name.startsWith("operator "))
        {
            code.writeln("/+");
            closeCommentWholeDecl = true;
        }
        scope (success)
            if (closeCommentWholeDecl)
                code.write("+/");

        ConditionMap!string codeType;
        CodeWriter codeAfterDeclSeq;
        codeAfterDeclSeq.indentStr = data.options.indent;
        bool afterTypeInDeclSeq;
        //if (data.sourceTokenManager.tokensLeft.data.length > 0)
        {
            if (d.tree.nonterminalID.nonterminalIDAmong!("SimpleDeclaration1",
                    "SimpleDeclaration3", "MemberDeclaration1",
                    "ParameterDeclaration", "Condition"))
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
                    semantic.logicSystem, condition);
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
        if (d.tree.name != "Condition" && d.tree.name != "ParameterDeclaration")
            code.write(";");
        if (nextEndToken.isValid && data.sourceTokenManager.tokensLeft.data.length > 0)
            writeComments(code, data,
                    data.sourceTokenManager.collectTokensUntilLineEnd(nextEndToken.location.end,
                        condition2));
        else if (d.tree.name != "Condition" && d.tree.name != "ParameterDeclaration")
            code.writeln();
    }
    else if (d.type == DeclarationType.varOrFunc
            && (d.tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal") || (d.flags & DeclarationFlags.function_) != 0))
    {
        DeclarationFlags combinedFlags = d.flags;
        bool hasFunctionBody = d.tree.name.startsWith("FunctionDefinition");
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

        string operatorFunctionName, operatorTemplateConstraint;
        bool commentWholeDecl;
        bool addExternD;
        if (d.name.startsWith("operator "))
        {
            if (d.name == "operator =" && forwardDecl is null && !hasFunctionBody)
            {
                if (!isStruct(parentClassTree, data))
                    return;
            }
            string op = d.name["operator ".length .. $];
            if (d.type2.kind == TypeKind.function_)
            {
                auto functionType = cast(FunctionType) d.type2.type;
                if (op.among("++", "--", "*")
                        && functionType.parameters.length == 0 && parentClassTree.isValid)
                {
                    operatorFunctionName = "opUnary(string op)";
                    operatorTemplateConstraint = " if (op == \"" ~ op ~ "\")";
                }
                if (op.among("&", "|", "+", "-")
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
                if (op.among("&=", "|=", "+=", "-=")
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

        QualType resultType = functionResultType(d.type2, semantic);

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
                    semantic.logicSystem, semantic.logicSystem.and(d.condition, condition));
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
                if (d.tree.nameOrContent == "FunctionDefinitionMember"
                        && d.tree.childs.length == 4 && d.tree.childs[2].nameOrContent == "delete")
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
                    "ParameterDeclaration", "Condition"))
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
            if (forwardDecl2.flags & DeclarationFlags.override_)
            {
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
                    "FunctionDeclaratorTrailing"), text(declList2[0].tree.name,
                    " ", locationStr(declList2[0].tree.start)));
            declList2 = declList2[1 .. $];
        }

        if (isConstructor || isDestructor)
        {
            //assert(declList2.length == 0, text(locationStr(d.tree.location), " ", declList2));
            //codeTmp.write(codeAfterDeclSeq.data);
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
        parseTreeToCodeTerminal!Tree(*codeTmp, "(");
        if (declList.length)
            codeTmp.write(declList[0].codeMiddle);
        parseTreeToCodeTerminal!Tree(*codeTmp, ")");
        if (declList.length)
            codeTmp.write(declList[0].codeAfter);
        codeTmp.write(operatorTemplateConstraint);

        if (d.tree.nameOrContent.startsWith("FunctionDefinition")
                && d.tree.childs.length == 4 && d.tree.childs[2].nameOrContent == "0")
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
                "FunctionDefinitionGlobal"))
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
                    semantic.logicSystem, semantic.logicSystem.true_);
            if (d.tree in d.scope_.childScopeByTree)
            {
                Scope classScope = d.scope_.childScopeByTree[d.tree];
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
                        if (instance.macroTranslation == MacroTranslation.enumValue)
                            code.writeln("enum ", instance.usedName, " =",
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
                    if (instance.macroTranslation == MacroTranslation.enumValue)
                        code.writeln("enum ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd], ";",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                    else if (instance.macroTranslation == MacroTranslation.alias_)
                        code.writeln("alias ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd], ";",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
                    else if (instance.macroTranslation == MacroTranslation.mixin_)
                        code.writeln("enum ", instance.usedName, " =",
                                instance.instanceCode[0 .. instance.realCodeStart],
                                "q{", instance.instanceCode[instance.realCodeStart .. instance.realCodeEnd], "};",
                                instance.instanceCode[instance.realCodeEnd
                                    .. $].withoutTrailingWhitespace);
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

string qualifyName(string name, Declaration d, DWriterData data, Scope currentScope,
        immutable(Formula)* condition)
{
    auto semantic = data.semantic;
    immutable(Formula)* conditionInOneModule = semantic.logicSystem.false_;
    immutable(Formula)* conditionInMultipleModules = semantic.logicSystem.false_;
    if (name in data.modulesBySymbol)
        foreach (filename, fcondition; data.modulesBySymbol[name])
            if (filename in data.importGraphHere || filename == data.currentFilename.moduleName)
            {
                immutable(Formula)* condition2 = fcondition;
                if (filename in data.importGraphHere)
                    condition2 = semantic.logicSystem.and(fcondition,
                            data.importGraphHere[filename].condition);
                conditionInMultipleModules = semantic.logicSystem.or(conditionInMultipleModules,
                        semantic.logicSystem.and(conditionInOneModule, condition2));
                conditionInOneModule = semantic.logicSystem.or(conditionInOneModule, condition2);
            }

    Scope realScope = d.scope_;
    if (realScope !is null && d.tree in d.scope_.childScopeByTree)
    {
        foreach (e; d.scope_.childScopeByTree[d.tree].extraParentScopes.entries)
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

    bool hasConflictingName = false;
    if (realScope !is null && realScope.parentScope is null && d.type == DeclarationType.type)
    {
        for (Scope s = currentScope; s !is null && s.parentScope !is null; s = s.parentScope)
        {
            auto x = name in s.symbols;
            if (x)
            {
                foreach (e2; (*x).entries)
                {
                    if (e2.data.type != DeclarationType.forwardScope && e2.data !is d
                            && (s !is realScope || e2.data.type != DeclarationType.type))
                    {
                        hasConflictingName = true;
                    }
                }
            }
        }
    }

    if (d in data.fileByDecl
        && ((realScope !is null && realScope.parentScope is null) || d.type == DeclarationType.macro_)
        && data.currentMacroInstance !is null
        && data.currentMacroInstance.macroDeclaration !is null
        && data.currentMacroInstance.macroDeclaration.type == DeclarationType.macro_
        && data.currentMacroInstance.macroTranslation == MacroTranslation.mixin_)
        name = data.options.importedSymbol ~ "!q{" ~ data.fileByDecl[d].moduleName ~ "}." ~ name;
    else if (d in data.fileByDecl && data.fileByDecl[d] != data.currentFilename
            && (!conditionInMultipleModules.isFalse || name in data.importedPackagesGraphHere))
        name = data.fileByDecl[d].moduleName ~ "." ~ name;
    else if (d in data.fileByDecl && data.fileByDecl[d] != data.currentFilename
            && realScope !is null && !realScope.tree.isValid
            && d.declarationSet.scope_.parentScope !is null)
        name = data.fileByDecl[d].moduleName ~ "." ~ name; // Namespace
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
    if (d.tree in d.scope_.childScopeByTree)
    {
        foreach (e; d.scope_.childScopeByTree[d.tree].extraParentScopes.entries)
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
    while (extraScope !is null && !extraScope.tree.isValid) // Skip over namespaces
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

bool isTypeBlacklisted(DWriterData data, QualType t)
{
    if (t.type is null)
        return false;
    if (t.kind == TypeKind.reference)
        t = t.allNext()[0];
    if (t.kind == TypeKind.rValueReference)
        return true;
    if (t.name == "initializer_list")
        return true;
    if (t.kind == TypeKind.typedef_)
    {
        RecordType recordType = cast(RecordType) t.type;
        Scope s = recordType.declarationSet.scope_;
        if (s.className.entries.length && s.className.entries[0].data == "chrono")
            return true;
    }
    if (t.kind == TypeKind.record)
    {
        RecordType recordType = cast(RecordType) t.type;
        Scope s = recordType.declarationSet.scope_;
        while (s.parentScope !is null && s.parentScope.parentScope !is null)
            s = s.parentScope;
        if (s.className.entries.length && s.className.entries[0].data == "std")
            return true;
    }
    return false;
}

bool isDeclarationBlacklisted(DWriterData data, Declaration d)
{
    auto inCache = d in data.blacklistedCache;
    if (inCache)
        return *inCache;
    bool r = isDeclarationBlacklistedImpl(data, d);
    data.blacklistedCache[d] = r;
    return r;
}

bool isDeclarationBlacklistedImpl(DWriterData data, Declaration d)
{
    if (d.location.context is null)
        return false;
    if (d.type == DeclarationType.varOrFunc && (d.flags & DeclarationFlags.function_) == 0
            && (d.flags & DeclarationFlags.static_) == 0 && !isRootNamespaceScope(d.scope_))
        return false;
    if ((d.flags & DeclarationFlags.virtual) || (d.flags & DeclarationFlags.override_))
        return false;
    if (d.flags & DeclarationFlags.friend)
        return true;
    if (d.flags & DeclarationFlags.templateSpecialization)
        return true;

    if (d.type == DeclarationType.varOrFunc
            && d.tree.name.startsWith("FunctionDefinition")
            && d.tree.childs.length == 4 && d.tree.childs[2].content.among( /*"delete",*/ "default"))
        return true;

    if (d.name.startsWith("emplace", "insertOne"))
        return false;

    QualType type = d.type2;
    if (type.kind == TypeKind.condition)
    {
        auto conditionType = cast(ConditionType) type.type;
        if (conditionType.conditions.length == 1)
            type = conditionType.types[0];
    }

    if (type.kind == TypeKind.function_)
    {
        auto functionType = cast(FunctionType) type.type;
        if (functionType.isRValueRef)
            return true;
        foreach (p; functionType.parameters)
        {
            if (isTypeBlacklisted(data, p))
                return true;
            QualType p2 = p;
            if (p2.kind == TypeKind.reference)
                p2 = p2.allNext()[0];
            if (d.name.among("operator <<", "operator >>") && p2.type !is null
                    && p2.name.among("QDebug", "QDataStream", "QTextStream"))
                return true;
        }
        if (isTypeBlacklisted(data, functionType.resultType))
            return true;
    }

    foreach_reverse (ref pattern; data.options.blacklist)
    {
        DeclarationMatch match;
        if (isDeclarationMatch(pattern, match, d, data.semantic))
            return true;
    }
    return false;
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

struct DependencyInfo
{
    immutable(Formula)* condition;
    bool outsideFunction;
    bool outsideMixin;
    LocationX locAdded;
}

DependencyInfo[Declaration] getDeclDependencies(Declaration d, DWriterData data)
{
    auto semantic = data.semantic;
    auto logicSystem = semantic.logicSystem;

    if (d.type == DeclarationType.forwardScope)
        return null;

    static DependencyInfo[Declaration][Declaration] cache;
    if (d in cache)
        return cache[d];

    DependencyInfo[Declaration] r;
    void add2(Declaration d2, immutable(Formula)* condition,
            bool outsideFunction, bool outsideMixin, LocationX locAdded)
    {
        if (isDeclarationBlacklisted(data, d2))
            return;
        if (d2.type == DeclarationType.namespace)
            return;
        if (d2.type == DeclarationType.macroParam)
            return;
        if (condition.isFalse)
            return;
        auto x = d2 in r;
        if (x)
            *x = DependencyInfo(semantic.logicSystem.or((*x).condition, condition),
                    (*x).outsideFunction || outsideFunction, (*x)
                        .outsideMixin || outsideMixin, (*x).locAdded);
        else
            r[d2] = DependencyInfo(condition, outsideFunction, outsideMixin, locAdded);
    }

    void add(Declaration d2, immutable(Formula)* condition, bool outsideFunction,
            bool outsideMixin, LocationX locAdded)
    {
        LocationRangeX loc1 = d.location;
        if (d.tree.isValid)
            loc1 = d.tree.location;
        LocationRangeX loc2 = d2.location;
        if (d2.tree.isValid)
            loc2 = d2.tree.location;
        if (d2.type == DeclarationType.type || (d.type != DeclarationType.macro_
                && d2.type == DeclarationType.varOrFunc && (d2.flags & DeclarationFlags.static_) != 0))
        {
            if (!hasCommonParentScope(d.scope_, d2.scope_))
            {
                auto conditionReachable = locationReachable(loc1, loc2, data);
                condition = semantic.logicSystem.and(condition, conditionReachable);
                if (conditionReachable.isFalse)
                {
                    return;
                }
            }
        }

        if (d2.type == DeclarationType.type
                && (d2.flags & DeclarationFlags.typedef_) != 0
                && isSelfTypedef(d2, data))
        {
            Declaration d3 = getSelfTypedefTarget(d2, data);
            if (d3 !is null && d3.type != DeclarationType.builtin)
                d2 = d3;
            else
                return;
        }

        immutable(Formula)* conditionLeft = condition;
        foreach (e; d2.realDeclaration.entries)
        {
            add2(e.data, semantic.logicSystem.and(e.condition, condition),
                    outsideFunction, outsideMixin, locAdded);
            conditionLeft = semantic.logicSystem.and(conditionLeft, e.condition.negated);
        }
        add2(d2, conditionLeft, outsideFunction, outsideMixin, locAdded);
    }

    void visitType(QualType type, immutable(Formula)* condition,
            bool outsideFunction, bool outsideMixin, LocationX locAdded)
    {
        if (type.type is null)
            return;
        if (type.kind == TypeKind.condition)
        {
            auto ctype = cast(ConditionType) type.type;
            foreach (i, x; ctype.types)
            {
                visitType(x, semantic.logicSystem.and(condition,
                        ctype.conditions[i]), outsideFunction, outsideMixin, locAdded);
            }
        }
        else if (type.kind == TypeKind.record)
        {
            RecordType recordType = cast(RecordType) type.type;
            if (recordType.declarationSet.scope_.isRootNamespaceScope)
                foreach (e; recordType.declarationSet.entries)
                {
                    if (e.data.type != DeclarationType.type)
                        continue;
                    if ((e.data.flags & DeclarationFlags.typedef_) != 0)
                        continue;
                    if (isDeclarationBlacklisted(data, e.data))
                        continue;
                    add(e.data, semantic.logicSystem.and(condition,
                            e.condition), outsideFunction, outsideMixin, locAdded);
                }
        }
        else if (type.kind == TypeKind.typedef_)
        {
            TypedefType typedefType = cast(TypedefType) type.type;
            bool blacklisted = false;
            if (typedefType.declarationSet !is null)
            {
                blacklisted = true;
                foreach (e; typedefType.declarationSet.entries)
                    if (!isDeclarationBlacklisted(data, e.data))
                        blacklisted = false;

                if (typedefType.declarationSet.scope_.isRootNamespaceScope)
                    foreach (e; typedefType.declarationSet.entries)
                    {
                        if (e.data.type != DeclarationType.type)
                            continue;
                        if ((e.data.flags & DeclarationFlags.typedef_) == 0)
                            continue;
                        if (isDeclarationBlacklisted(data, e.data))
                            continue;
                        add(e.data, semantic.logicSystem.and(condition,
                                e.condition), outsideFunction, outsideMixin, locAdded);
                    }
            }
        }
        else if (type.kind == TypeKind.builtin)
        {
            if (data.options.builtinCppTypes)
            {
                string translation;
                switch (type.name)
                {
                case "long":
                    translation = "cpp_long";
                    break;
                case "unsigned_long":
                    translation = "cpp_ulong";
                    break;
                case "long_long":
                    translation = "cpp_longlong";
                    break;
                case "unsigned_long_long":
                    translation = "cpp_ulonglong";
                    break;
                default:
                }
                if (translation.length)
                    add(data.dummyDeclaration(translation, "core.stdc.config"),
                            condition, outsideFunction, outsideMixin, locAdded);
            }
        }
        else
        {
            foreach (x; type.allNext())
                visitType(x, condition, outsideFunction, outsideMixin, locAdded);
        }
    }

    enum Flags
    {
        none = 0,
        addNormal = 1,
        addInterpolatMixins = 2,
        all = addNormal | addInterpolatMixins,
        inTemplate = 4
    }

    bool[Tree][MacroDeclarationInstance] macroDone;

    void visitTree(Tree tree, immutable(Formula)* condition, Flags flags,
            MacroDeclarationInstance currentMacroInstance, bool outsideFunction, bool outsideMixin)
    {
        if (!tree.isValid)
            return;
        if (tree.nameOrContent == "UsingDeclaration")
            return;
        if (tree.nameOrContent == "FunctionBody")
            outsideFunction = false;
        Tree parent = getRealParent(tree, semantic);
        if (currentMacroInstance)
        {
            if (currentMacroInstance in macroDone && tree in macroDone[currentMacroInstance])
                return;
            macroDone[currentMacroInstance][tree] = true;
        }
        if (tree in data.macroReplacement)
        {
            bool foundThisMacro;
            bool isValueMacro;
            bool isMixinMacro;
            bool isMacroParam;
            bool hasSubMacros;
            void onDep(MacroDeclarationInstance instance2)
            {
                if (instance2 is currentMacroInstance)
                {
                    foundThisMacro = true;
                    foreach (x; instance2.extraDeps)
                    {
                        onDep(x);
                    }
                    foundThisMacro = false;
                    return;
                }
                if (currentMacroInstance !is null && !foundThisMacro)
                {
                    foreach (x; instance2.extraDeps)
                    {
                        onDep(x);
                    }
                    return;
                }
                hasSubMacros = true;

                foreach (name, param; instance2.params)
                    foreach (instanceParam; param.instances)
                        foreach (t; instanceParam.macroTrees)
                            visitTree(t, condition, flags, instanceParam, outsideFunction, outsideMixin);

                if (instance2.macroDeclaration !is null && instance2.macroDeclaration.type == DeclarationType.macroParam)
                    isMacroParam = true;

                if ((flags & Flags.addInterpolatMixins)
                        || instance2.macroTranslation != MacroTranslation.mixin_)
                    if (instance2.macroTranslation != MacroTranslation.none
                            && instance2.macroDeclaration !is null
                            && !instance2.macroDeclaration.name.among("Q_OBJECT"))
                        add(instance2.macroDeclaration, condition,
                                outsideFunction, outsideMixin, tree.start);
                if (instance2.macroTranslation == MacroTranslation.enumValue
                        || instance2.macroTranslation == MacroTranslation.alias_)
                {
                    isValueMacro = true;
                    return;
                }
                if (instance2.macroTranslation == MacroTranslation.mixin_)
                {
                    isMixinMacro = true;
                }
                foreach (t; instance2.macroTrees)
                    visitTree(t, condition, flags, instance2, outsideFunction, outsideMixin && !isMixinMacro);
            }

            onDep(data.macroReplacement[tree]);
            if (isValueMacro || isMacroParam || hasSubMacros)
                return;
        }
        if (semantic.extraInfo(tree).declarations.length
                && !(tree.nameOrContent == "ParameterDeclarationAbstract"
                    && (flags & Flags.inTemplate) != 0))
        {
            bool used;
            foreach (d; semantic.extraInfo(tree).declarations)
            {
                if (!isDeclarationBlacklisted(data, d))
                    used = true;
            }
            if (!used)
                return;
        }
        if (flags & Flags.addNormal)
        {
            foreach (x; semantic.extraInfo(tree).referenced.entries)
            {
                if (x.data.scope_.isRootNamespaceScope)
                {
                    foreach (e; x.data.entries)
                    {
                        if (e.data.flags & DeclarationFlags.templateSpecialization)
                            continue;
                        if (e.data.tree.isValid && e.data.tree.nonterminalID == nonterminalIDFor!"Enumerator")
                            visitType(semantic.extraInfo(tree).type, condition,
                                    outsideFunction, outsideMixin, tree.start);
                    }
                }
            }
            if (semantic.extraInfo(tree).referenced.entries.length)
            {
                ConditionMap!Declaration realDecl;
                findRealDecl(tree, realDecl, condition, data, true /*allowType*/ , d.scope_);
                foreach (e; realDecl.entries)
                {
                    if (e.data.flags & DeclarationFlags.templateSpecialization)
                        continue;
                    if (e.data.scope_.isRootNamespaceScope)
                    {
                        add(e.data, e.condition, outsideFunction, outsideMixin, tree.start);
                    }
                }
            }
            if (!tree.nameOrContent.among("PostfixExpression") && (!parent.isValid
                    || !parent.nonterminalID.nonterminalIDAmong!("PostfixExpression"))
                    && !isTreeExpression(tree, semantic) && !(parent.isValid
                        && parent.nameOrContent == "QualifiedId"
                        && tree.nameOrContent == "NameIdentifier"))
                visitType(semantic.extraInfo(tree).type, condition,
                        outsideFunction, outsideMixin, tree.start);
            if (currentMacroInstance is null)
            {
                immutable(Formula)* needsCastCondition = semantic.logicSystem.false_;
                immutable(Formula)* needsCastStaticArrayCondition = semantic.logicSystem.false_;
                calcNeedsCast(needsCastCondition, needsCastStaticArrayCondition,
                        data, tree, condition, null, null);

                if (!needsCastCondition.isFalse || !needsCastStaticArrayCondition.isFalse)
                    visitType(semantic.extraInfo2(tree).convertedType,
                            condition, outsideFunction, outsideMixin, tree.start);
            }
        }

        auto dummyDeclaration = getDummyDeclaration(tree, data, semantic);
        if (dummyDeclaration !is null)
            add2(dummyDeclaration, condition, outsideFunction, outsideMixin, tree.start);

        foreach (i, c; tree.childs)
        {
            immutable(Formula)* condition2 = condition;
            if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                ConditionTree ctree = tree.toConditionTree;
                condition2 = semantic.logicSystem.and(condition, ctree.conditions[i]);
            }
            visitTree(c, condition2, flags, null, outsideFunction, outsideMixin);
        }
        if (tree.nameOrContent.startsWith("MemberDeclaration"))
        {
            foreach (d; semantic.extraInfo(tree).declarations)
            {
                if (d.type != DeclarationType.varOrFunc)
                    continue;
                if (isDeclarationBlacklisted(data, d))
                    continue;
                foreach (e; d.realDeclaration.entries)
                {
                    foreach (d2, di; getDeclDependencies(e.data, data))
                        add2(d2, di.condition, di.outsideFunction, di.outsideMixin, tree.start);
                }
            }
        }
    }

    if (d.type == DeclarationType.type
            && (d.flags & DeclarationFlags.typedef_) != 0
            && isSelfTypedef(d, data))
    {
        cache[d] = r;
        return r;
    }
    visitTree(d.tree, d.condition, Flags.all, null, true, true);
    foreach (e; d.realDeclaration.entries)
    {
        add2(e.data, e.condition, true, true, d.location.start);
    }

    if (d.type == DeclarationType.macro_)
    {
        MacroDeclaration macroDeclaration = cast(MacroDeclaration) d;
        foreach (instance; macroDeclaration.instances)
        {
            if (instance.macroTranslation == MacroTranslation.enumValue
                    || instance.macroTranslation == MacroTranslation.alias_)
            {
                foreach (t; instance.macroTrees)
                    visitTree(t, d.condition, Flags.all, instance, true, true);
            }
        }
    }

    foreach (t; findParentTemplateDeclarations(d.tree, semantic))
    {
        visitTree(t.childs[2], d.condition, Flags.all | Flags.inTemplate, null, true, true);
    }

    cache[d] = r;

    return r;
}

void addDeclaration(TodoList!Declaration todo, Declaration d, DWriterData data)
{
    auto semantic = data.semantic;

    if (d.type == DeclarationType.forwardScope)
        return;

    Appender!(Declaration[]) declsApp;
    foreach (d2, _; getDeclDependencies(d, data))
    {
        if (d2.type == DeclarationType.dummy)
            continue;
        declsApp.put(d2);
    }
    auto decls = declsApp.data;

    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));
    foreach (d2; decls)
    {
        todo.addAfter!({ addDeclaration(todo, d2, data); })(d2);
    }
}

string getFreeName(string name, DFilename filename,
        immutable(Formula)* condition, DWriterData data, Scope scope_ = null)
{
    if (scope_ !is null && scope_.parentScope is null)
        scope_ = null;

    size_t minNumVariants;
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

bool includeDeclsForFile(DWriterData data, string filename)
{
    return data.options.includeAllDecls
        || filename in data.inputFilesSet
        || data.options.includeDeclFilenamePatterns.match(filename);
}

void selectDeclarations(DWriterData data)
{
    auto semantic = data.semantic;

    string getDeclCategory(Declaration d, ref IteratePPVersions ppVersion)
    {
        string category;
        if (d.type == DeclarationType.varOrFunc)
        {
            if (d.declaratorTree.nonterminalID == nonterminalIDFor!"InitDeclarator"
                    && (d.flags & DeclarationFlags.function_) == 0)
                category = "Init ";
            category ~= "VarOrFunc";
            if ((d.flags & DeclarationFlags.function_) == 0
                    && (d.flags & DeclarationFlags.static_) != 0)
            {
                category ~= " file:" ~ d.location.context.rootFilename;
            }
            if ((d.flags & DeclarationFlags.function_) != 0)
            {
                category ~= " type: " ~ typeToString(filterType(d.type2,
                        ppVersion.condition, semantic, FilterTypeFlags.replaceRealTypes
                        | FilterTypeFlags.simplifyFunctionType | FilterTypeFlags.removeTypedef));
            }
        }
        else if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0)
        {
            QualType t = chooseType(d.type2, ppVersion, true);

            category = text("typedef ", cast(void*) t.type, " ", t.qualifiers,
                    " ", getDeclarationFilename(d, data).moduleName);
        }
        else if (d.type == DeclarationType.type)
            category = "type";
        Scope s = d.scope_;
        if (d.scope_ !is null && d.tree in d.scope_.childScopeByTree)
        {
            foreach (e; d.scope_.childScopeByTree[d.tree].extraParentScopes.entries)
            {
                if (e.data.type != ExtraScopeType.namespace)
                    continue;
                if (!isInCorrectVersion(ppVersion, e.condition))
                    continue;
                s = e.data.scope_;
                break;
            }
        }
        while (s !is null && s.tree.isValid) // not namespace
            s = s.parentScope;
        if (s !is null)
            category ~= " namespace " ~ s.toString();
        return category;
    }

    Appender!(Declaration[]) tmpDeclarationBuffer;
    bool[Declaration] added;
    void onScope0(Scope s)
    {
        foreach (name, entries; s.symbols)
        {
            foreach (e; entries.entries ~ entries.entriesRedundant)
            {
                if (isDeclarationBlacklisted(data, e.data))
                    continue;
                if (e.data.type == DeclarationType.namespace)
                    continue;
                if (e.data !in added)
                {
                    tmpDeclarationBuffer.put(e.data);
                    added[e.data] = true;
                }
                foreach (e2; e.data.realDeclaration.entries)
                {
                    if (isDeclarationBlacklisted(data, e2.data))
                        continue;
                    if (e2.data !in added)
                    {
                        tmpDeclarationBuffer.put(e2.data);
                        added[e2.data] = true;
                    }
                }
            }
        }
        foreach (name, s2; s.childNamespaces)
            onScope0(s2);
    }

    onScope0(semantic.rootScope);
    tmpDeclarationBuffer.data.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));

    immutable(Formula)*[string][string] hasNonForwardDecl;
    foreach (d; tmpDeclarationBuffer.data)
    {
        if (d.flags & DeclarationFlags.forward)
            continue;
        if (d.name.length == 0)
            continue;
        if ((d.flags & DeclarationFlags.typedef_) != 0)
            continue;
        /*if (d.type == DeclarationType.type && (d.flags & DeclarationFlags.typedef_) != 0
            && d.name == typeToCode(d.type2, data, d.condition, null))
            continue; // self alias*/

        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, d.condition);

            string category = getDeclCategory(d, ppVersion);

            immutable(Formula)* prev = semantic.logicSystem.false_;
            auto e = category in hasNonForwardDecl;
            if (!e)
            {
                hasNonForwardDecl[category] = null;
                e = category in hasNonForwardDecl;
            }
            if (d.name in *e)
                prev = (*e)[d.name];
            (*e)[d.name] = semantic.logicSystem.or(prev, ppVersion.condition);
        }
    }

    immutable(Formula)*[string][string] doneForwardDecl;

    immutable(Formula)*[Declaration] forwardDecls;
    foreach (d; tmpDeclarationBuffer.data)
    {
        if (d.type == DeclarationType.forwardScope)
            continue;
        if (d.isRedundant)
        {
            forwardDecls[d] = d.condition;
            continue;
        }
        immutable(Formula)* skipForward = semantic.logicSystem.false_;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination,
                    semantic.logicSystem, d.condition);

            string category = getDeclCategory(d, ppVersion);
            if ((d.flags & DeclarationFlags.forward) != 0
                    || (d.flags & DeclarationFlags.typedef_) != 0)
            {
                auto e = category in hasNonForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
                e = category in doneForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
            }
            if (d.type == DeclarationType.varOrFunc && d.declaratorTree.name != "InitDeclarator"
                    && (d.flags & DeclarationFlags.function_) == 0)
            {
                string category2 = "Init " ~ category;
                auto e = category2 in hasNonForwardDecl;
                if (e && d.name in *e)
                    skipForward = semantic.logicSystem.or(skipForward,
                            semantic.logicSystem.and(ppVersion.condition, (*e)[d.name]));
            }
            if (d.flags & DeclarationFlags.enumerator)
                continue;
            if (d.name.among("size_t", "ptrdiff_t"))
                continue;

            if ((d.flags & DeclarationFlags.forward) != 0
                    || (d.flags & DeclarationFlags.typedef_) != 0)
            {
                if (category !in doneForwardDecl)
                    doneForwardDecl[category] = null;
                if (d.name !in doneForwardDecl[category])
                    doneForwardDecl[category][d.name] = ppVersion.condition;
                else
                    doneForwardDecl[category][d.name] = semantic.logicSystem.or(
                            doneForwardDecl[category][d.name], ppVersion.condition);
            }
        }
        forwardDecls[d] = skipForward;
    }
    data.forwardDecls = forwardDecls;

    tmpDeclarationBuffer.clear();
    void onScope(Scope s)
    {
        foreach (name, entries; s.symbols)
        {
            foreach (e; entries.entries ~ entries.entriesRedundant)
            {
                if (isDeclarationBlacklisted(data, e.data))
                    continue;
                if (e.data.type == DeclarationType.namespace)
                    continue;
                immutable(LocationContext)* locContext = e.data.location.context;
                if (locContext is null)
                    continue;
                while (locContext !is null && locContext.name.length)
                    locContext = locContext.prev;
                if (locContext.contextDepth != 1)
                    continue;
                if (!includeDeclsForFile(data, locContext.filename))
                    continue;
                tmpDeclarationBuffer.put(e.data);
            }
        }
        foreach (name, s2; s.childNamespaces)
            onScope(s2);
    }

    onScope(semantic.rootScope);

    foreach (key, d; data.sourceTokenManager.macroDeclarations)
    {
        if (includeDeclsForFile(data, d.location.context.filename))
        {
            tmpDeclarationBuffer.put(d);
        }
    }
    tmpDeclarationBuffer.put(data.sourceTokenManager.commentDeclarations.data);

    auto decls = tmpDeclarationBuffer.data;

    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));
    auto todo = new TodoList!Declaration;
    foreach (d; decls)
    {
        todo.addAfter!({ addDeclaration(todo, d, data); })(d);
    }
    decls = todo.data;
    decls.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));

    foreach (d; decls)
    {
        if (d.type == DeclarationType.forwardScope)
            continue;
        DFilename filenameNoExt = getDeclarationFilename(d, data);
        if (d.name.among("size_t", "ptrdiff_t"))
            continue;
        if (d.name.among("__assert_fail", "assert"))
            continue;

        data.declsByFile[filenameNoExt] ~= d;
    }

    data.decls = decls;

    foreach (d; decls)
    {
        if (d.type.among(DeclarationType.forwardScope, DeclarationType.dummy, DeclarationType.namespace, DeclarationType.namespaceBegin, DeclarationType.namespaceEnd))
            continue;
        if (d !in forwardDecls)
            forwardDecls[d] = semantic.logicSystem.false_;
    }

    foreach (name, ref decls2; data.declsByFile)
    {
        decls2.sort!((a, b) => cmpDeclarationLoc(a, b, semantic));

        ImportInfo[string] neededImports;
        bool[string] neededPackages;
        foreach (d; decls2)
        {
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
                if (d2.type != DeclarationType.dummy && d2 !in forwardDecls)
                    continue;
                immutable(Formula)* condition = semantic.logicSystem.and(
                        semantic.logicSystem.and(semantic.logicSystem.and(d.condition,
                        d2.condition), forwardDecls[d].negated), t2[1]);
                if (d2 in forwardDecls)
                    condition = semantic.logicSystem.and(condition, forwardDecls[d2].negated);
                if (filenameNoExt != name.moduleName && !condition.isFalse)
                {
                    ImportInfo importInfo;
                    if (filenameNoExt in neededImports)
                    {
                        importInfo = neededImports[filenameNoExt];
                        importInfo.condition = semantic.logicSystem.or(importInfo.condition,
                                condition);
                        importInfo.outsideFunction |= t2[2];
                    }
                    else
                    {
                        importInfo = new ImportInfo;
                        neededImports[filenameNoExt] = importInfo;
                        importInfo.condition = condition;
                        importInfo.outsideFunction = t2[2];
                    }
                    if (importInfo.examples.length < 5)
                    {
                        importInfo.examples ~= ImportExample(d, d2, t2[3]);
                    }
                    neededPackages[filenameNoExt.packageName] = true;
                }
            }
        }
        data.importGraph[name] = neededImports;
        data.importedPackagesGraph[name] = neededPackages;
    }
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
        applyMacroInstances(data, mergedSemantic,
                mergedFile.locationContextInfoMap.getLocationContextInfo(null));
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
