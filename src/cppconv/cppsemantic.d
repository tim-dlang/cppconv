
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cppsemantic;
import core.time;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppparserwrapper;
import cppconv.cpptree;
import cppconv.cpptype;
import cppconv.ecs;
import cppconv.filecache;
import cppconv.mergedfile;
import cppconv.parallelparser;
import cppconv.preproc;
import cppconv.runcppcommon;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.stdio;
import std.traits;
import std.typetuple;

alias getDummyGrammarInfo = cppconv.parallelparser.getDummyGrammarInfo;

alias Location = LocationX;
alias Tree = CppParseTree;

alias ParserWrapper = cppconv.cppparserwrapper.ParserWrapper;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

alias TypedefType = cppconv.cpptype.TypedefType; // conflicts with std.typecons.TypedefType

struct TreeExtraInfo
{
    QualType type;
    ConditionMap!DeclarationSet referenced;
    Declaration[] declarations;
    Tree parent;
    size_t sourceTrees;
    QualType contextType;
}

struct TreeExtraInfo2
{
    QualType convertedType;
    ConditionMap!(long) constantValue;
    bool preventStringToPointer;
    immutable(Formula)* labelNeedsGoto;
    bool acessingBitField;
    ConditionMap!(AccessSpecifier) accessSpecifier;
}

struct DeclarationExtra2
{
    ConditionMap!Tree defaultInit;
}

template FieldNameTupleAll(T)
{
    static if (BaseTypeTuple!T.length && !is(BaseTypeTuple!T[0] == Type))
        alias FieldNameTupleAll = AliasSeq!(FieldNameTupleAll!(BaseTypeTuple!T[0]),
                FieldNameTuple!T);
    else
        alias FieldNameTupleAll = FieldNameTuple!T;
}

struct DelayedSemantic
{
    SemanticRunInfo semantic;
    Tree tree;
    Tree parent;
    immutable(Formula)* condition;
}

class Semantic
{
    LogicSystem logicSystem;

    Scope rootScope;
    Scope fakeTemplateScope;
    MergedTreeData[const(Tree)] mergedTreeDatas;
    bool[Tree] treesVisited;
    LocationContextMap locationContextMap;
    size_t[string] generatedNameCounters;
    Declaration[DeclarationKey] declarationCache;
    MergedFile*[RealFilename] mergedFileByName;
    bool isCPlusPlus;

    DelayedSemantic[] delayedSemantics;
    bool collectingDelayedSemantics;

    EntityManager entityManager;
    EntityID[const(Tree)] treeToID;
    ComponentManager!TreeExtraInfo componentExtraInfo;
    ComponentManager!TreeExtraInfo2 componentExtraInfo2;
    DeclarationExtra2*[Declaration] declarationExtra2Map;

    static struct InitListState
    {
        bool inArray;
        Declaration[] fields;
        size_t currentField;
    }
    ConditionMap!InitListState currentInitListStates;

    EntityID treeID(const Tree tree)
    {
        auto x = tree in treeToID;
        if (x)
            return *x;
        treeToID[tree] = entityManager.addEntity(0);
        return treeToID[tree];
    }

    static size_t numTreeExtraInfoCreated;
    ref TreeExtraInfo extraInfo(const Tree tree)
    {
        return componentExtraInfo.get(treeID(tree));
    }

    ref TreeExtraInfo2 extraInfo2(const Tree tree)
    {
        return componentExtraInfo2.get(treeID(tree));
    }

    ref MergedTreeData mergedTreeData(const Tree tree)
    {
        auto x = tree in mergedTreeDatas;
        if (x)
            return *x;
        mergedTreeDatas[tree] = MergedTreeData();
        auto r = &mergedTreeDatas[tree];
        r.conditions.length = tree.childs.length;
        foreach (ref c; r.conditions)
            c = logicSystem.false_;
        r.mergedCondition = logicSystem.false_;
        return *r;
    }

    ref DeclarationExtra2 declarationExtra2(Declaration d)
    {
        auto x = d in declarationExtra2Map;
        if (x)
            return **x;
        declarationExtra2Map[d] = new DeclarationExtra2();
        return *declarationExtra2Map[d];
    }

    static string buildTypeCaches()
    {
        string code;
        foreach (kind; __traits(allMembers, TypeKind)[1 .. $])
        {
            enum kindU = () {
                string r = (kind[0] - 'a' + 'A') ~ kind[1 .. $];
                if (r[$ - 1] == '_')
                    r = r[0 .. $ - 1];
                return r;
            }();

            mixin("alias T = " ~ kindU ~ "Type;");

            code ~= "    struct " ~ kindU ~ "CacheKey\n    {\n";
            foreach (name; FieldNameTupleAll!T)
            {
                code ~= "        typeof(__traits(getMember, " ~ kindU
                    ~ "Type, \"" ~ name ~ "\")) " ~ name ~ ";\n";
            }
            code ~= "    }\n";
            code ~= "    " ~ kindU ~ "Type[" ~ kindU ~ "CacheKey] typeCache" ~ kindU ~ ";\n";
            if (kindU != "Condition")
            {
                code ~= "    " ~ kindU ~ "Type get" ~ kindU ~ "Type(";
                foreach (name; FieldNameTupleAll!T)
                {
                    code ~= "typeof(__traits(getMember, " ~ kindU ~ "Type, \""
                        ~ name ~ "\")) " ~ name ~ ", ";
                }
                code ~= ")\n";
                code ~= "    {\n";
                code ~= "        auto key = " ~ kindU ~ "CacheKey(";
                foreach (name; FieldNameTupleAll!T)
                {
                    code ~= name ~ ", ";
                }
                code ~= ");\n";
                code ~= "        auto inCache = key in typeCache" ~ kindU ~ ";\n";
                code ~= "        if (inCache)\n";
                code ~= "            return *inCache;\n";
                code ~= "        " ~ kindU ~ "Type type = new " ~ kindU ~ "Type();\n";
                foreach (name; FieldNameTupleAll!T)
                {
                    alias T2 = typeof(__traits(getMember, T, name));
                    static if (is(T2 == U[], U))
                        code ~= "        key." ~ name ~ " = key." ~ name ~ ".dup;\n";
                    code ~= "        type." ~ name ~ " = key." ~ name ~ ";\n";
                }
                code ~= "        typeCache" ~ kindU ~ "[key] = type;\n";
                code ~= "        assert(type.kind == TypeKind." ~ kind ~ ");\n";
                code ~= "        return type;\n";
                code ~= "    }\n";
            }
        }
        return code;
    }

    mixin(buildTypeCaches());

    QualType getConditionType(QualType[] types, const immutable(Formula)*[] conditions)
    {
        static struct E
        {
            QualType t;
            immutable(Formula)* c;
        }

        static Appender!(E[]) tmpBuffer;
        static Appender!(QualType[]) tmpBufferTypes;
        static Appender!(immutable(Formula)*[]) tmpBufferConditions;
        scope (exit)
        {
            tmpBuffer.clear();
            tmpBufferTypes.clear();
            tmpBufferConditions.clear();
        }
        foreach (i; 0 .. types.length)
        {
            if (types[i].kind == TypeKind.condition)
            {
                auto conditionType = cast(ConditionType) types[i].type;
                foreach (j; 0 .. conditionType.conditions.length)
                {
                    tmpBuffer.put(E(conditionType.types[j].withExtraQualifiers(types[i].qualifiers),
                            logicSystem.and(conditions[i], conditionType.conditions[j])));
                }
            }
            else
            {
                tmpBuffer.put(E(types[i], conditions[i]));
            }
        }
        E[] list = tmpBuffer.data;
        list.sort!"a.c.opCmp(*b.c) < 0"();
        size_t count = 0;
        foreach (i; 0 .. list.length)
        {
            if (list[i].c.isFalse)
                continue;
            if (count && list[i].t == list[count - 1].t)
            {
                list[count - 1].c = logicSystem.or(list[count - 1].c, list[i].c);
            }
            else
            {
                list[count] = list[i];
                count++;
            }
        }
        list = list[0 .. count];

        Qualifiers commonQualifiers = ~Qualifiers.none;
        foreach (ref e; list)
            commonQualifiers &= e.t.qualifiers;
        foreach (ref e; list)
            e.t.qualifiers &= ~commonQualifiers;

        foreach (i; 0 .. list.length)
        {
            tmpBufferTypes.put(list[i].t);
            tmpBufferConditions.put(list[i].c);
        }

        auto key = ConditionCacheKey(tmpBufferTypes.data,
                cast(immutable(Formula*)[]) tmpBufferConditions.data,);
        auto inCache = key in typeCacheCondition;
        ConditionType type;
        if (inCache)
            type = *inCache;
        else
        {
            type = new ConditionType();
            key.types = key.types.dup;
            type.types = key.types;
            key.conditions = key.conditions.dup;
            type.conditions = key.conditions;
            typeCacheCondition[key] = type;
        }
        return QualType(type, commonQualifiers);
    }

    QualType sizeType_;
    QualType sizeType()
    {
        if (sizeType_.type !is null)
            return sizeType_;
        QualType[] types = [
            QualType(getBuiltinType("unsigned")),
            QualType(getBuiltinType("unsigned_long"))
        ];
        immutable Formula*[] conditions = [
            logicSystem.notLiteral("defined(__LP64__)"),
            logicSystem.literal("defined(__LP64__)")
        ];
        sizeType_ = getConditionType(types, conditions);
        return sizeType_;
    }

    QualType wcharType_;
    QualType wcharType()
    {
        if (wcharType_.type !is null)
            return wcharType_;
        QualType[] types = [
            QualType(getBuiltinType("char16")), QualType(getBuiltinType("char32"))
        ];
        immutable Formula*[] conditions = [
            logicSystem.notLiteral("defined(_WIN32)"),
            logicSystem.literal("defined(_WIN32)")
        ];
        wcharType_ = getConditionType(types, conditions);
        return wcharType_;
    }

    bool[QualType] hasMutableIndirectionCache;
    string[Declaration] fullyQualifiedNameCache;
}

struct SemanticRunInfo
{
    Semantic semantic;
    alias semantic this;
    Scope currentScope;
    bool afterMerge;
    immutable(LocationContext)* currentFile;
    immutable(Formula)* instanceCondition;
}

struct ClassSpecifierInfo
{
    string className;
    string[] namespaces;
    string key;
    LocationRangeX identifierLocation = LocationX.invalid;
    QualType[] parentTypes;
    size_t inNestedNameSpecifier;
    QualType namespaceType;
}

struct DeclaratorInfo
{
    string name;
    string[] namespaces;
    LocationRangeX identifierLocation = LocationX.invalid;
    bool anyIsFunction;
    bool isDestructor;
    Tree[] typeConstructors;
    QualType type;
    byte bitfieldSize;
    size_t inNestedNameSpecifier;
    Scope parameterScope;
    DeclarationFlags flags;
    QualType namespaceType;
    bool isTemplateSpecialization;
}

struct SimpleDeclarationInfo
{
    DeclarationFlags flags;
    string[] builtinTypeParts;
    Qualifiers qualifiers;
    Type type;
    LocationX start;
    Tree tree;
    Tree classSpecifier;
    bool hasAnyTypeSpecifier;
    Scope namespaceScope;
}

struct ParameterInfo
{
    QualType[] parameters;
    Tree[] parameterTrees;
    bool isVariadic;
    bool isConst;
    bool isRef;
    bool isRValueRef;
    size_t neededParameters;
}

void collectParameters(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref ParameterInfo info, bool hasDefault)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!collectParameters(c, ppVersion, semantic, info, hasDefault);
        }
    }
    else if (tree.nodeType == NodeType.merged)
    {
        iteratePPVersions!collectParameters(tree.childs[ppVersion.combination.next(cast(uint)$)],
                ppVersion, semantic, info, hasDefault);
    }
    else if (tree.nodeType == NodeType.token)
    {
        if (tree.content == "...")
            info.isVariadic = true;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParametersAndQualifiers")
    {
        iteratePPVersions!collectParameters(tree.childs[0], ppVersion, semantic, info, hasDefault);
        iteratePPVersions!collectParameters(tree.childs[1], ppVersion, semantic, info, hasDefault);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"Parameters")
    {
        iteratePPVersions!collectParameters(tree.childs[1], ppVersion, semantic, info, hasDefault);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParameterDeclaration"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParameterDeclarationAbstract")
    {
        if (tree.childs[$ - 2].nameOrContent == "=")
            hasDefault = true;
        info.parameterTrees ~= tree;
        iteratePPVersions!collectParameters(tree.childs[1], ppVersion, semantic, info, hasDefault);
    }
    else if (tree.name.endsWith("Declarator"))
    {
        info.parameters ~= semantic.extraInfo(tree).type;
        if (!hasDefault)
            info.neededParameters = info.parameters.length;
    }
    else if (tree.name.endsWith("CvQualifier"))
    {
        if (tree.childs[0].content == "const")
            info.isConst = true;
    }
    else if (tree.name.endsWith("RefQualifier"))
    {
        if (tree.childs[0].content == "&&")
            info.isRValueRef = true;
        if (tree.childs[0].content == "&")
            info.isRef = true;
    }
}

void collectParameterExprs(Tree tree, ref IteratePPVersions ppVersion,
        Semantic semantic, ref Tree[] parameterExprs, ref bool hasNonterminal)
{
    if (!tree.isValid)
        return;
    if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!collectParameterExprs(c, ppVersion, semantic,
                    parameterExprs, hasNonterminal);
        }
    }
    else if (tree.nodeType == NodeType.token)
    {
        assert(tree.content == "," || tree.content == "..." || tree.content == "",
                text(locationStr(tree.start), " ", tree.content));
        if (tree.content == ",")
        {
            if (!hasNonterminal)
            {
                writeln("WARNING: unexpected or duplicate comma in arg list: ",
                        locationStr(tree.start), " ", ppVersion.condition.toString);
                parameterExprs ~= Tree.init;
            }
            hasNonterminal = false;
        }
    }
    else
    {
        if (!hasNonterminal)
            parameterExprs ~= tree;
        else
            writeln("WARNING: multiple nonterminals in arg list: ",
                    locationStr(tree.start), " ", ppVersion.condition.toString);
        hasNonterminal = true;
    }
}

void analyzeDeclarator(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref DeclaratorInfo info, QualType type)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.merged)
    {
        iteratePPVersions!analyzeDeclarator(tree.childs[ppVersion.combination.next(cast(uint)$)],
                ppVersion, semantic, info, type);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParametersAndQualifiers")
    {
        info.anyIsFunction = true;
        info.parameterScope = semantic.currentScope.childScopeByTree[tree];
    }
    else if (tree.name.endsWith("Initializer"))
    {
    }
    else if (tree.name.endsWith("BracedInitList"))
    {
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ArrayDeclarator"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ArrayAbstractDeclarator")
    {
        ArrayType arrayType = semantic.getArrayType(type, tree);
        auto type2 = QualType(arrayType, Qualifiers.none);
        Tree innerDeclarator = tree.childByName("innerDeclarator");
        if (!innerDeclarator.isValid)
            info.type = type2;
        iteratePPVersions!analyzeDeclarator(innerDeclarator, ppVersion, semantic, info, type2);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PtrDeclarator"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"PtrAbstractDeclarator")
    {
        bool isReference;
        assert(tree.childs[0].nonterminalID == nonterminalIDFor!"PtrOperator");
        if (tree.childs[0].childs[0].nameOrContent == "&")
            isReference = true;
        Type pointerType;
        if (tree.childs[0].childs[0].nameOrContent == "&")
            pointerType = semantic.getReferenceType(type);
        else if (tree.childs[0].childs[0].nameOrContent == "&&")
            pointerType = semantic.getRValueReferenceType(type);
        else
            pointerType = semantic.getPointerType(type);
        QualType type2 = QualType(pointerType, Qualifiers.none);
        Tree innerDeclarator = tree.childByName("innerDeclarator");
        if (!innerDeclarator.isValid)
            info.type = type2;
        iteratePPVersions!analyzeDeclarator(innerDeclarator, ppVersion, semantic, info, type2);
    }
    else if (tree.name.startsWith("FunctionDeclarator")
            || tree.name.startsWith("FunctionAbstractDeclarator"))
    {
        QualType combinedType;
        foreach (combination2; iterateCombinations())
        {
            ParameterInfo parameterInfo;

            IteratePPVersions ppVersion2 = IteratePPVersions(combination2, semantic.logicSystem,
                    ppVersion.condition, ppVersion.instanceCondition, semantic.mergedTreeDatas);

            Tree conversionFuncId = tree;
            while (conversionFuncId.isValid)
            {
                if (conversionFuncId.nonterminalID == nonterminalIDFor!"ConversionFunctionId")
                    break;
                else if (conversionFuncId.nonterminalID == nonterminalIDFor!"DeclaratorId")
                    conversionFuncId = ppVersion2.chooseTree(conversionFuncId.childs[$ - 1]);
                else if (conversionFuncId.hasChildWithName("innerDeclarator"))
                    conversionFuncId = ppVersion2.chooseTree(
                            conversionFuncId.childByName("innerDeclarator"));
                else
                    conversionFuncId = Tree.init;
            }
            QualType resultType = type;
            if (conversionFuncId.isValid)
                resultType = semantic.extraInfo(ppVersion.chooseTree(conversionFuncId.childs[1]))
                    .type;

            iteratePPVersions!collectParameters(tree.childs[1], ppVersion2,
                    semantic, parameterInfo, false);

            if (parameterInfo.parameters.length == 1 && parameterInfo.parameters[0].type !is null
                    && parameterInfo.parameters[0].kind == TypeKind.builtin
                    && parameterInfo.parameters[0].type.name == "void")
                parameterInfo.parameters = [];
            if (parameterInfo.parameters.length == 1 && parameterInfo.parameters[0].type !is null
                    && parameterInfo.parameters[0].kind == TypeKind.condition)
            {
                auto ctype = cast(ConditionType) parameterInfo.parameters[0].type;
                bool allVoid = true;
                foreach (c; ctype.types)
                    if (c.type is null || c.kind != TypeKind.builtin || c.type.name != "void")
                        allVoid = false;
                if (allVoid)
                    parameterInfo.parameters = [];
            }

            FunctionType functionType = semantic.getFunctionType(resultType,
                    parameterInfo.parameters, parameterInfo.isVariadic,
                    parameterInfo.isConst, parameterInfo.isRef,
                    parameterInfo.isRValueRef, parameterInfo.neededParameters);
            QualType type2 = QualType(functionType, Qualifiers.none);
            if (combinedType.type is null)
                combinedType = type2;
            else
                combinedType = combineTypes(combinedType, type2, null,
                        ppVersion2.condition, semantic);
        }

        info.anyIsFunction = true;
        Tree innerDeclarator = tree.childByName("innerDeclarator");
        if (!innerDeclarator.isValid)
            info.type = combinedType;
        iteratePPVersions!analyzeDeclarator(innerDeclarator, ppVersion,
                semantic, info, combinedType);
        iteratePPVersions!analyzeDeclarator(tree.childByName("parameters"),
                ppVersion, semantic, info, combinedType);
        iteratePPVersions!analyzeDeclarator(tree.childs[$ - 1], ppVersion,
                semantic, info, combinedType);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"SimpleTemplateId")
    {
        iteratePPVersions!analyzeDeclarator(tree.childs[0], ppVersion, semantic, info, type);
        if (tree.childs[2].nodeType == NodeType.array)
        {
            foreach (c; tree.childs[2].childs)
                if (c.nameOrContent == "Literal")
                    info.isTemplateSpecialization = true;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"FunctionDefinitionHead")
    {
        info.anyIsFunction = true;
        iteratePPVersions!analyzeDeclarator(tree.childs[1], ppVersion, semantic, info, type);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NestedNameSpecifier")
    {
        info.inNestedNameSpecifier++;
        foreach (c; tree.childs)
            iteratePPVersions!analyzeDeclarator(c, ppVersion, semantic, info, type);
        info.inNestedNameSpecifier--;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        assert(info.name.length == 0, text(locationStr(tree.location), " ",
                info.name, " ", tree.childs[0].name));
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        if (info.inNestedNameSpecifier)
        {
            info.namespaces ~= tree.childs[0].content;
        }
        else
        {
            info.name = tree.childs[0].content;
            info.identifierLocation = tree.location;
            info.type = type;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"OperatorFunctionId")
    {
        assert(info.name.length == 0, text(locationStr(tree.location), " ",
                info.name, " ", tree.childs[0].name));
        assert(tree.childs[0].nodeType == NodeType.token);
        enforce(tree.childs[1].nonterminalID == nonterminalIDFor!"OverloadableOperator");
        info.name = "operator ";
        foreach (c; tree.childs[1].childs)
            info.name ~= c.content;
        info.identifierLocation = tree.location;
        info.type = type;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ConversionFunctionId")
    {
        assert(info.name.length == 0, text(locationStr(tree.location), " ",
                info.name, " ", tree.childs[0].name));
        assert(tree.childs[0].nodeType == NodeType.token);
        info.name = "operator cast";
        info.identifierLocation = tree.location;
        info.type = type;
    }
    else if (tree.nameOrContent == "MemberDeclarator" && tree.childs.length == 5
            && tree.childs[3].nameOrContent == ":")
    {
        // Identifier? AttributeSpecifierSeq VirtSpecifierSeq? ":" ConstantExpression
        assert(info.name.length == 0, text(info.name, " ", tree.childs[0].name));
        info.name = (!tree.childs[0].isValid) ? "" : tree.childs[0].content;
        info.identifierLocation = tree.location;
        info.type = type;
        Tree expr = tree.childs[4];
        if (expr.nonterminalID == nonterminalIDFor!"Literal")
            info.bitfieldSize = cast(byte) /*TODO*/ parseIntLiteral(expr.childs[0].content);
        else if (expr.nonterminalID == nonterminalIDFor!"AdditiveExpression")
        {
            if (expr.childs[0].name != "Literal" || expr.childs[2].name != "Literal")
            {
                info.bitfieldSize = 65;
                return;
            }
            assert(expr.childs[0].nonterminalID == nonterminalIDFor!"Literal",
                    text(locationStr(tree.start), " ", tree));
            assert(expr.childs[2].nonterminalID == nonterminalIDFor!"Literal",
                    text(locationStr(tree.start), " ", tree));
            ulong lhs = parseIntLiteral(expr.childs[0].childs[0].name);
            ulong rhs = parseIntLiteral(expr.childs[2].childs[0].name);
            if (expr.childs[1].name == "+")
                lhs = lhs + rhs;
            else if (expr.childs[1].name == "-")
                lhs = lhs - rhs;
            else
                assert(false, text(locationStr(tree.start), " ", tree));
            info.bitfieldSize = cast(byte) lhs;
        }
        else
            assert(false, text(locationStr(tree.start), " ", tree));
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"FakeAbstractDeclarator")
    {
        assert(info.name.length == 0, text(info.name, " ", tree.childs[0].name));
        info.type = type;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"VirtSpecifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        string name = tree.childs[0].content;
        if (name == "override")
            info.flags |= DeclarationFlags.override_;
        if (name == "final")
            info.flags |= DeclarationFlags.final_;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TypeId")
    {
        iteratePPVersions!analyzeDeclarator(tree.childs[1], ppVersion, semantic, info, type);
    }
    else if (tree.nameOrContent == "UnqualifiedId" && tree.childs.length == 2
            && tree.childs[0].nameOrContent == "~")
    {
        info.isDestructor = true;
        iteratePPVersions!analyzeDeclarator(tree.childs[1], ppVersion, semantic, info, type);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclaratorId"
            && tree.hasChildWithName("nestedName"))
    {
        foreach (c; tree.childs)
            iteratePPVersions!analyzeDeclarator(c, ppVersion, semantic, info, type);
        info.namespaceType = semantic.extraInfo(tree.childByName("nestedName")).type;
    }
    else
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeDeclarator(c, ppVersion, semantic, info, type);
        }
    }
}

void analyzeClassSpecifierBaseClause(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref ClassSpecifierInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"BaseSpecifier")
    {
        info.parentTypes ~= semantic.extraInfo(tree.childs[$ - 1]).type;
    }
    else
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeClassSpecifierBaseClause(c, ppVersion, semantic, info);
        }
    }
}

void analyzeClassSpecifier(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref ClassSpecifierInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.merged)
    {
        iteratePPVersions!analyzeClassSpecifier(tree.childs[ppVersion.combination.next(cast(uint)$)],
                ppVersion, semantic, info);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"SimpleTemplateId")
    {
        iteratePPVersions!analyzeClassSpecifier(tree.childs[0], ppVersion, semantic, info);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"BaseClause")
    {
        iteratePPVersions!analyzeClassSpecifierBaseClause(tree.childs[1], ppVersion, semantic, info);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NestedNameSpecifier")
    {
        info.inNestedNameSpecifier++;
        foreach (c; tree.childs)
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        info.inNestedNameSpecifier--;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        if (info.className.length)
            return;
        assert(info.className.length == 0, text(info.className, " ", tree.childs[0].name));
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        if (info.inNestedNameSpecifier)
        {
            info.namespaces ~= tree.childs[0].content;
        }
        else
        {
            info.className = tree.childs[0].content;
            info.identifierLocation = tree.location;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassHeadName")
    {
        foreach (c; tree.childs)
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        info.namespaceType = semantic.extraInfo(tree.childByName("nestedName")).type;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier"
            && tree.childs[$ - 1].nodeType == NodeType.token)
    {
        assert(info.className.length == 0, text(info.className, " ", tree.childs[$ - 1].name));
        info.className = tree.childs[$ - 1].content;
        info.identifierLocation = tree.childs[$ - 1].location;
        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TypeParameter"
            && tree.hasChildWithName("name") && tree.childByName("name").isValid)
    {
        assert(info.className.length == 0, text(info.className, " ",
                tree.childByName("name").name, "  ", locationStr(tree.location)));
        info.className = tree.childByName("name").content;
        info.identifierLocation = tree.childByName("name").location;
        /*        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        }*/
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EnumHead")
    {
        assert(info.className.length == 0, text(info.className, " ", tree.childs[$ - 1].name));
        if (!tree.hasChildWithName("name"))
        {
            info.className = "";
            info.identifierLocation = tree.location;
        }
        else if (tree.childs[$ - 2].nodeType == NodeType.token)
        {
            assert(tree.childs[$ - 2].nodeType == NodeType.token);
            info.className = tree.childs[$ - 2].content;
            info.identifierLocation = tree.childs[$ - 2].location;
        }
        else
        {
            assert(tree.childs[$ - 2].nodeType == NodeType.nonterminal);
            assert(tree.childs[$ - 2].name == "Identifier?");
            assert(tree.childs[$ - 2].childs.length == 1);
            assert(tree.childs[$ - 2].childs[0].isToken);
            info.className = tree.childs[$ - 2].childs[0].name;
            info.identifierLocation = tree.childs[$ - 2].location;
        }
        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EnumKey")
    {
        assert(info.key.length == 0, text(info.key, " ", tree.childs[0].name));
        assert(tree.childs.length >= 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        info.key = tree.childs[0].content;
        if (tree.childs.length >= 2)
            info.key ~= " " ~ tree.childs[1].content;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassKey")
    {
        assert(info.key.length == 0, text(info.key, " ", tree.childs[0].name));
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        info.key = tree.childs[0].content;
    }
    else if (tree.name.endsWith("ClassBody"))
    {
        if (ppVersion.combination.prefixDone)
            return;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EnumSpecifier")
    {
        // only EnumHead
        iteratePPVersions!analyzeClassSpecifier(tree.childs[0], ppVersion, semantic, info);
    }
    else
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!analyzeClassSpecifier(c, ppVersion, semantic, info);
        }
    }
}

bool isTemplateSpecialization(Tree tree, ref IteratePPVersions ppVersion)
{
    if (tree.nodeType == NodeType.token)
    {
        return false;
    }
    else if (tree.nodeType == NodeType.merged)
    {
        return iteratePPVersions!isTemplateSpecialization(
                tree.childs[ppVersion.combination.next(cast(uint)$)], ppVersion);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"SimpleTemplateId")
    {
        return true;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassHeadName")
    {
        return iteratePPVersions!isTemplateSpecialization(tree.childs[$ - 1], ppVersion);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassHead")
    {
        if (tree.hasChildWithName("name"))
            return iteratePPVersions!isTemplateSpecialization(tree.childByName("name"), ppVersion);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier")
    {
        return iteratePPVersions!isTemplateSpecialization(tree.childs[0], ppVersion);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier")
    {
        return tree.childs.length == 5;
    }
    return false;
}

void analyzeSimpleDeclaration(Tree tree, immutable(Formula)* condition,
        ref SemanticRunInfo semantic, ref IteratePPVersions ppVersion, ref SimpleDeclarationInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
        if (tree.content == "typedef")
            if (isInCorrectVersion(ppVersion, condition))
                info.flags |= DeclarationFlags.typedef_;
    }
    else if (tree.name.startsWith("TypeKeyword"))
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        if (isInCorrectVersion(ppVersion, condition))
        {
            string name = tree.childs[0].content;
            info.builtinTypeParts ~= name;
        }
        info.hasAnyTypeSpecifier = true;
    }
    else if (tree.name.startsWith("CvQualifier"))
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        if (isInCorrectVersion(ppVersion, condition))
        {
            string name = tree.childs[0].content;
            if (name == "const")
                info.qualifiers |= Qualifiers.const_;
            else if (name == "volatile")
                info.qualifiers |= Qualifiers.volatile_;
            else if (name == "restrict")
                info.qualifiers |= Qualifiers.restrict_;
        }
        info.hasAnyTypeSpecifier = true;
    }
    else if (tree.name.startsWith("StorageClassSpecifier"))
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        if (isInCorrectVersion(ppVersion, condition))
        {
            string name = tree.childs[0].content;
            if (name == "static")
                info.flags |= DeclarationFlags.static_;
            if (name == "extern")
                info.flags |= DeclarationFlags.extern_;
        }
        info.hasAnyTypeSpecifier = true;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"FunctionSpecifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        if (isInCorrectVersion(ppVersion, condition))
        {
            string name = tree.childs[0].content;
            if (name == "inline")
                info.flags |= DeclarationFlags.inline;
            if (name == "virtual")
                info.flags |= DeclarationFlags.virtual;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclSpecifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);

        if (isInCorrectVersion(ppVersion, condition))
        {
            string name = tree.childs[0].content;
            if (name == "friend")
                info.flags |= DeclarationFlags.friend;
            if (name == "constexpr")
                info.flags |= DeclarationFlags.constExpr;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"AlignmentSpecifier")
    {
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("NameIdentifier",
            "SimpleTypeSpecifierNoKeyword", "SimpleTemplateId", "DecltypeSpecifier"))
    {
        if (isInCorrectVersion(ppVersion, condition))
        {
            info.type = semantic.extraInfo(tree).type.type;
            info.hasAnyTypeSpecifier = true;
        }
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        foreach (i; 0 .. tree.childs.length)
        {
            auto subTreeCondition = mdata.conditions[i];
            if (semantic.instanceCondition !is null)
                subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                        semantic.instanceCondition, semantic.logicSystem);

            auto condition2 = semantic.logicSystem.and(semantic.logicSystem.or(subTreeCondition,
                    semantic.logicSystem.and(mdata.mergedCondition,
                    semantic.logicSystem.literal("#merged"))), condition);
            iterateTreeConditions!analyzeSimpleDeclaration(tree.childs[i],
                    condition2, semantic, ppVersion, info);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("ClassSpecifier",
            "ElaboratedTypeSpecifier", "EnumSpecifier"))
    {
        if (isInCorrectVersion(ppVersion, condition))
        {
            if (info.classSpecifier.isValid
                    && simplifyMergedCondition(ppVersion.condition, semantic.logicSystem).isFalse)
                return;

            if (info.classSpecifier.isValid)
            {
                writeln("double class specifier ", locationStr(tree.start),
                        " ", ppVersion.condition.toString);
                assert(false);
            }
            info.classSpecifier = tree;

            info.type = semantic.extraInfo(tree).type.type;
        }
        info.hasAnyTypeSpecifier = true;
    }
    else if (tree.name.endsWith("ClassBody"))
    {
        assert(false);
    }
    else if (tree.name.endsWith("FunctionBody"))
    {
        if (ppVersion.combination.prefixDone)
            return;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"FunctionDefinitionHead")
    {
        iterateTreeConditions!analyzeSimpleDeclaration(tree.childs[0],
                condition, semantic, ppVersion, info);
    }
    else if (tree.name.endsWith("Declarator"))
    {
    }
    else if (tree.name.endsWith("SimpleDeclaration1"))
    {
        iterateTreeConditions!analyzeSimpleDeclaration(tree.childs[0],
                condition, semantic, ppVersion, info);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"InitializerClause")
    {
    }
    else
    {
        foreach (c; tree.childs)
        {
            iterateTreeConditions!analyzeSimpleDeclaration(c, condition,
                    semantic, ppVersion, info);
        }
    }
}

alias collectRecordFields = iterateTreeConditions!collectRecordFieldsImpl;
void collectRecordFieldsImpl(Tree tree, immutable(Formula)* condition,
        Semantic semantic, ref IteratePPVersions ppVersion, ref Declaration[] declarations)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (i; 0 .. tree.childs.length)
        {
            collectRecordFields(tree.childs[i], condition, semantic, ppVersion, declarations);
        }
    }
    else if (tree.nodeType == NodeType.nonterminal
            && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            collectRecordFields(ctree.childs[i], semantic.logicSystem.and(subTreeCondition,
                    condition), semantic, ppVersion, declarations);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier")
    {
        collectRecordFields(tree.childs[1], condition, semantic, ppVersion, declarations);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassBody")
    {
        collectRecordFields(tree.childs[1], condition, semantic, ppVersion, declarations);
    }
    else if (tree.name.startsWith("SimpleDeclaration") || tree.name.startsWith("MemberDeclaration")
            || tree.nonterminalID.nonterminalIDAmong!("FunctionDefinitionMember",
                "FunctionDefinitionGlobal", "MemberDeclaration" /*, "ParameterDeclaration", "ParameterDeclarationAbstract"*/ ))
    {
        foreach (d; semantic.extraInfo(tree).declarations)
        {
            if ((d.flags & DeclarationFlags.static_) != 0)
                continue;
            if ((d.flags & DeclarationFlags.function_) != 0)
                continue;
            if (d.type == DeclarationType.type)
                continue;

            if (isInCorrectVersion(ppVersion, d.condition))
            {
                declarations ~= d;
            }
        }
    }
}

void analyzeSwitch(Semantic semantic, Tree tree, immutable(Formula)* condition,
        ref immutable(Formula)* afterStatement)
{
    if (!tree.isValid)
        return;
    if (condition.isFalse)
        return;

    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (i; 0 .. tree.childs.length)
        {
            analyzeSwitch(semantic, tree.childs[i], condition, afterStatement);
        }
    }
    else if (tree.nodeType == NodeType.nonterminal
            && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        foreach (i; 0 .. ctree.childs.length)
        {
            auto subTreeCondition = ctree.conditions[i];

            analyzeSwitch(semantic, ctree.childs[i],
                    semantic.logicSystem.and(subTreeCondition, condition), afterStatement);
        }
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("Statement", "CompoundStatement"))
    {
        foreach (i; 0 .. tree.childs.length)
        {
            analyzeSwitch(semantic, tree.childs[i], condition, afterStatement);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"LabelStatement")
    {
        semantic.extraInfo2(tree).labelNeedsGoto = afterStatement;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"JumpStatement")
    {
        afterStatement = semantic.logicSystem.and(afterStatement, condition.negated);
    }
    else if (tree.name.endsWith("Statement"))
    {
        afterStatement = semantic.logicSystem.or(afterStatement, condition);
    }
}

struct CheckValidDeclarationInfo
{
    bool isDecl;
    bool isNotDecl;
}

void checkValidDeclaration(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref CheckValidDeclarationInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidDeclaration(c, ppVersion, semantic, info);
        }
    }
    else if (tree.name.startsWith("SimpleDeclaration")
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclSpecifierSeq")
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidDeclaration(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TypeKeyword")
    {
        info.isDecl = true;
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        string name = tree.childs[0].name;

        Declaration[] ds = lookupName(name, semantic.currentScope, ppVersion,
                LookupNameFlags.followForwardScopes | LookupNameFlags.strictCondition);

        foreach (d; ds)
        {
            if (d.type == DeclarationType.type)
                info.isDecl = true;
            if (d.type == DeclarationType.varOrFunc)
                info.isNotDecl = true;
        }
    }
}

void checkValidParam(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref CheckValidDeclarationInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidParam(c, ppVersion, semantic, info);
        }
    }
    else if (tree.name.startsWith("NoptrDeclarator") || tree.name.startsWith("PtrDeclarator")
            || tree.name.startsWith("FunctionDeclarator")
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParametersAndQualifiers"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"Parameters"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParameterDeclaration"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ParameterDeclarationAbstract"
            || tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclSpecifierSeq")
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidParam(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        string name = tree.childs[0].content;

        Declaration[] ds = lookupName(name, semantic.currentScope, ppVersion,
                LookupNameFlags.followForwardScopes | LookupNameFlags.strictCondition);

        foreach (d; ds)
        {
            if (d.type == DeclarationType.type)
                info.isDecl = true;
            if (d.type == DeclarationType.varOrFunc)
                info.isNotDecl = true;
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"SimpleTemplateId")
    {
        iteratePPVersions!checkValidParam(tree.childs[0], ppVersion, semantic, info);
    }
}

void checkValidTypeId(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref CheckValidDeclarationInfo info)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidTypeId(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TypeId")
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidTypeId(c, ppVersion, semantic, info);
        }
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        string name = tree.childs[0].content;

        Declaration[] ds = lookupName(name, semantic.currentScope, ppVersion,
                LookupNameFlags.followForwardScopes | LookupNameFlags.strictCondition);

        foreach (d; ds)
        {
            if (d.type == DeclarationType.type)
                info.isDecl = true;
            if (d.type == DeclarationType.varOrFunc)
                info.isNotDecl = true;
        }
    }
}

void checkValidConstructor(Tree tree, ref IteratePPVersions ppVersion,
        ref SemanticRunInfo semantic, ref string constructorName)
{
    if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (c; tree.childs)
        {
            iteratePPVersions!checkValidConstructor(c, ppVersion, semantic, constructorName);
        }
    }
    else if (tree.hasChildWithName("innerDeclarator"))
    {
        iteratePPVersions!checkValidConstructor(tree.childByName("innerDeclarator"),
                ppVersion, semantic, constructorName);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"DeclaratorId")
    {
        iteratePPVersions!checkValidConstructor(tree.childs[$ - 1], ppVersion,
                semantic, constructorName);
    }
    else if (tree.nonterminalID == ParserWrapper.nonterminalIDFor!"NameIdentifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        constructorName = tree.childs[0].content;
    }
}

Tree getRealParent(Tree tree, Semantic semantic, size_t* indexInParent = null)
{
    Tree realParent = semantic.extraInfo(tree).parent;
    while (realParent.isValid && (realParent.nodeType != NodeType.nonterminal
            || realParent.nonterminalID == CONDITION_TREE_NONTERMINAL_ID))
    {
        tree = realParent;
        realParent = semantic.extraInfo(realParent).parent;
    }
    if (realParent.isValid && indexInParent !is null)
    {
        foreach (i, t; realParent.childs)
        {
            if (t is tree)
            {
                *indexInParent = i;
                return realParent;
            }
        }
        assert(false);
    }
    return realParent;
}

string normalizeBuiltinTypeParts(string[] parts)
{
    bool isUnsigned;
    bool isSigned;
    string baseType;
    size_t numShort, numLong;
    foreach (part; parts)
    {
        if (part == "unsigned")
        {
            isUnsigned = true;
            assert(!isSigned);
            //isSigned = false;
        }
        else if (part == "signed")
        {
            //isUnsigned = false;
            assert(!isUnsigned);
            isSigned = true;
        }
        else if (part == "short")
            numShort++;
        else if (part == "long")
            numLong++;
        else
        {
            if (part == "_Bool")
                part = "bool";
            if (part.startsWith("__builtin_"))
                part = part["__builtin_".length .. $];
            if (part.startsWith("__"))
                part = part["__".length .. $];
            if (part.startsWith("uint"))
                part = "unsigned_int" ~ part["uint".length .. $];
            if (part.endsWith("_t"))
                part = part[0 .. $ - 2];
            if (baseType.length && baseType == part)
                continue;
            assert(baseType.length == 0, text(parts));
            baseType = part;
        }
    }

    string t;
    if (isUnsigned)
        t ~= "unsigned_";
    if (isSigned && baseType == "char")
        t ~= "signed_";
    assert(numShort == 0 || numLong == 0);
    foreach (k; 0 .. numShort)
        t ~= "short_";
    foreach (k; 0 .. numLong)
        t ~= "long_";
    if (baseType.length == 0 || baseType == "int")
    {
        if (baseType.length == 0)
            assert(numShort > 0 || numLong > 0 || isSigned || isUnsigned);
        if (t.length == 0)
            t = "int";
        else
            t = t[0 .. $ - 1];
    }
    else
    {
        assert(numShort == 0);
        assert(numLong == 0 || baseType == "double",
                text(parts));
        t ~= baseType;
    }
    return t;
}

QualType getDeclSpecType(Semantic semantic, ref SimpleDeclarationInfo info)
{
    QualType type;

    if (info.type !is null)
    {
        type = QualType(info.type, info.qualifiers);
    }
    else if (info.builtinTypeParts.length)
    {
        string t = normalizeBuiltinTypeParts(info.builtinTypeParts);
        type = QualType(semantic.getBuiltinType(t), info.qualifiers);
    }
    return type;
}

template ConflictHandler(alias F)
{
    alias check = F;
}

@ConflictHandler!((Tree mergedTree, Tree initDecl, Tree funcDecl) {
    if (initDecl.nonterminalID == nonterminalIDFor!"InitDeclarator")
        return true;
    if (mergedTree.nonterminalID == nonterminalIDFor!"InitDeclaratorList")
    {
        if (initDecl.nodeType == NodeType.array && funcDecl.nodeType == NodeType.array
            && initDecl.childs.length == 1 && funcDecl.childs.length == 1
            && initDecl.childs[0].nonterminalID == nonterminalIDFor!"InitDeclarator")
            return true;
    }
    return false;
})void handleConflictInitDeclarator(ref SemanticRunInfo semantic, Tree mergedTree, Tree initDecl, Tree funcDecl,
        ref immutable(Formula)* conditionInitDecl,
        ref immutable(Formula)* conditionFuncDecl, immutable(Formula)* condition)
{
    if (initDecl.nodeType == NodeType.array)
        initDecl = initDecl.childs[0];
    if (funcDecl.nodeType == NodeType.array)
        funcDecl = funcDecl.childs[0];
    with (semantic.logicSystem)
    {
        size_t i;
        foreach (combination; iterateCombinations())
        {
            /*foreach (k;0..indent)
                write(" ");
            writeln("  combination ", i, " checkValidParam");*/
            CheckValidDeclarationInfo info;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                    condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iteratePPVersions!checkValidParam(funcDecl, ppVersion, semantic, info);

            if (info.isDecl && !info.isNotDecl)
                conditionFuncDecl = or(conditionFuncDecl, ppVersion.condition);
            else if (!info.isDecl && info.isNotDecl)
                conditionInitDecl = or(conditionInitDecl, ppVersion.condition);
            i++;
        }
    }
}

@ConflictHandler!((Tree mergedTree, Tree typeofExpr, Tree typeofType) {
    return mergedTree.name.startsWith("TypeIdOrExpression")
        && typeofType.nonterminalID == nonterminalIDFor!"TypeId";
}) void handleConflictTypeof(ref SemanticRunInfo semantic, Tree mergedTree, Tree typeofExpr, Tree typeofType,
        ref immutable(Formula)* conditionTypeofExpr,
        ref immutable(Formula)* conditionTypeofType, immutable(Formula)* condition)
{
    with (semantic.logicSystem)
    {
        size_t i;
        foreach (combination; iterateCombinations())
        {
            CheckValidDeclarationInfo info;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                    condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iteratePPVersions!checkValidTypeId(typeofType, ppVersion, semantic, info);

            if (info.isDecl && !info.isNotDecl)
                conditionTypeofType = or(conditionTypeofType, ppVersion.condition);
            else if (!info.isDecl && info.isNotDecl)
                conditionTypeofExpr = or(conditionTypeofExpr, ppVersion.condition);
            i++;
        }
    }
}

@ConflictHandler!((Tree mergedTree, Tree memberDeclaration1, Tree memberDeclaration2) {
    return memberDeclaration1.nonterminalID == nonterminalIDFor!"MemberDeclaration1"
        && memberDeclaration2.nonterminalID == nonterminalIDFor!"MemberDeclaration2";
}) void handleConflictMemberDeclaration(ref SemanticRunInfo semantic,
        Tree mergedTree, Tree memberDeclaration1, Tree memberDeclaration2,
        ref immutable(Formula)* conditionMemberDeclaration1, ref immutable(
            Formula)* conditionMemberDeclaration2, immutable(Formula)* condition)
{
    with (semantic.logicSystem)
    {
        conditionMemberDeclaration2 = or(conditionMemberDeclaration2, condition);
    }
}

@ConflictHandler!((Tree mergedTree, Tree decl1, Tree decl2) {
    return mergedTree.nonterminalID == nonterminalIDFor!"TemplateParameter"
        && decl1.nonterminalID == nonterminalIDFor!"ParameterDeclarationAbstract"
        && decl2.nonterminalID == nonterminalIDFor!"TypeParameter";
}) void handleConflictTemplateParameter(ref SemanticRunInfo semantic, Tree mergedTree, Tree decl1,
        Tree decl2, ref immutable(Formula)* cond1, ref immutable(Formula)* cond2,
        immutable(Formula)* condition)
{
    with (semantic.logicSystem)
    {
        cond2 = or(cond2, condition);
    }
}

@ConflictHandler!((Tree mergedTree, Tree constructorDecl, Tree otherDecl) {
    if (mergedTree.nonterminalID == nonterminalIDFor!"MemberDeclaration1")
    {
        if (constructorDecl.name.startsWith("MemberDeclaration1")
            && otherDecl.name.startsWith("MemberDeclaration1")
            && !constructorDecl.childs[0].isValid && otherDecl.childs[0].isValid)
        {
            return true;
        }
    }
    if (mergedTree.nonterminalID == nonterminalIDFor!"MemberSpecification")
    {
        assert(constructorDecl.nodeType == NodeType.array);
        assert(otherDecl.nodeType == NodeType.array);
        if (constructorDecl.childs.length == 2
            && constructorDecl.childs[0].nonterminalID == nonterminalIDFor!"FunctionDefinitionMember"
            && otherDecl.childs.length == 1
            && otherDecl.childs[0].nonterminalID == nonterminalIDFor!"MemberDeclaration1"
            && otherDecl.childs[0].childs[0].isValid)
        {
            return true;
        }
    }
    return false;
})void handleConflictConstructor(ref SemanticRunInfo semantic, Tree mergedTree,
        Tree constructorDecl, Tree otherDecl, ref immutable(
            Formula)* conditionConstructorDecl,
        ref immutable(Formula)* conditionOtherDecl, immutable(Formula)* condition)
{
    if (constructorDecl.nodeType == NodeType.array)
        constructorDecl = constructorDecl.childs[0];
    if (constructorDecl.nonterminalID == nonterminalIDFor!"FunctionDefinitionMember")
        constructorDecl = constructorDecl.childs[0];
    if (otherDecl.nodeType == NodeType.array)
        otherDecl = otherDecl.childs[0];
    with (semantic.logicSystem)
    {
        size_t i;
        enforce(semantic.currentScope.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ClassSpecifier");
        foreach (combination; iterateCombinations())
        {
            string foundConstructorName;
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                    condition, semantic.instanceCondition, semantic.mergedTreeDatas);
            iteratePPVersions!checkValidConstructor(constructorDecl.childs[1],
                    ppVersion, semantic, foundConstructorName);

            QualType classType = semantic.extraInfo(semantic.currentScope.tree).type;
            classType = chooseType(classType, ppVersion, true);
            assert(classType.kind == TypeKind.record);

            if (foundConstructorName.length && foundConstructorName == classType.name)
                conditionConstructorDecl = or(conditionConstructorDecl, ppVersion.condition);
            else
                conditionOtherDecl = or(conditionOtherDecl, ppVersion.condition);
            i++;
        }
    }
}

enum ConflictExpressionFlags
{
    none = 0,
    inType = 1,
    inTemplate = 2,
    inCall = 4,
    notTemplate = 8,
}

void handleConflictExpression(Tree tree, ref immutable(Formula)* goodConditionStrict,
        ref immutable(Formula)* goodCondition,
        ref SemanticRunInfo semantic, ConflictExpressionFlags flags, QualType* contextType = null, immutable(Formula)** isDependentName = null)
{
    if (!tree.isValid)
        return;

    if (tree.nodeType == NodeType.array)
    {
        foreach (i, ref c; tree.childs)
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition, semantic, flags, null, isDependentName);
        }
    }
    else if (tree.nodeType == NodeType.token)
    {
    }
    else if (tree.nodeType == NodeType.merged && tree.nonterminalID == nonterminalIDFor!"TypeIdOrExpression")
    {
        goodConditionStrict = semantic.logicSystem.false_;
        goodCondition = semantic.logicSystem.false_;
    }
    else if (tree.nodeType == NodeType.merged)
    {
        auto mdata = &semantic.mergedTreeData(tree);

        static int mergeDepth;
        mergeDepth++;
        scope (exit)
            mergeDepth--;

        size_t qualifiedIdIndex = size_t.max;
        foreach (i, c; tree.childs)
        {
            if (c.nonterminalID == nonterminalIDFor!"QualifiedId")
                qualifiedIdIndex = i;
        }

        immutable(Formula)* resultGoodCondition = semantic.logicSystem.false_;
        immutable(Formula)* resultGoodConditionStrict = semantic.logicSystem.false_;
        immutable(Formula)* allCondition = semantic.logicSystem.false_;
        immutable(Formula)* allConditionStrict = semantic.logicSystem.false_;
        immutable(Formula)* badCondition = goodCondition;
        immutable(Formula)*[] goodConditionsStrict2;
        goodConditionsStrict2.length = tree.childs.length;
        immutable(Formula)*[] goodConditions2;
        goodConditions2.length = tree.childs.length;
        immutable(Formula)*[] extraConditions;
        extraConditions.length = tree.childs.length;
        immutable(Formula)* origIsDependentName = isDependentName ? *isDependentName : semantic.logicSystem.false_;
        QualType[] childContextTypes;
        QualType origContextType;
        size_t defaultTree = size_t.max;
        if (contextType !is null)
        {
            childContextTypes.length = tree.childs.length;
            origContextType = *contextType;
        }
        foreach (i, ref c; tree.childs)
        {
            immutable(Formula)* isDependentName2 = origIsDependentName;
            if (qualifiedIdIndex != size_t.max
                    && c.nonterminalID.nonterminalIDAmong!("TypeId",
                        "SimpleTypeSpecifierNoKeyword"))
            {
                defaultTree = qualifiedIdIndex;
            }
            goodConditionsStrict2[i] = goodCondition;
            goodConditions2[i] = goodCondition;
            extraConditions[i] = semantic.logicSystem.true_;
            Tree c2 = c;
            if (c.nonterminalID == CONDITION_TREE_NONTERMINAL_ID && c.childs.length == 2 && !c.childs[1].isValid)
            {
                extraConditions[i] = c.toConditionTree.conditions[0];
                c2 = c.childs[0];
            }
            if (contextType !is null)
                *contextType = origContextType;
            handleConflictExpression(c2, goodConditionsStrict2[i],
                    goodConditions2[i], semantic, flags, contextType, &isDependentName2);
            if (contextType !is null)
                childContextTypes[i] = *contextType;

            if (isDependentName)
            {
                *isDependentName = semantic.logicSystem.or(*isDependentName, isDependentName2);
            }
        }
        foreach (i; 0 .. tree.childs.length)
            foreach (j; 0 .. i)
            {
                allCondition = semantic.logicSystem.or(allCondition,
                        semantic.logicSystem.and(goodConditions2[i], goodConditions2[j]));
                allConditionStrict = semantic.logicSystem.or(allConditionStrict,
                        semantic.logicSystem.and(goodConditionsStrict2[i],
                            goodConditionsStrict2[j]));
            }

        immutable(Formula)* defaultCondition = semantic.logicSystem.false_;
        immutable(Formula)* defaultConditionStrict = semantic.logicSystem.false_;
        if (defaultTree != size_t.max)
        {
            defaultCondition = goodConditions2[defaultTree];
            defaultConditionStrict = goodConditionsStrict2[defaultTree];
        }

        foreach (i; 0 .. tree.childs.length)
        {
            goodConditionsStrict2[i] = semantic.logicSystem.and(goodConditionsStrict2[i],
                    allConditionStrict.negated);
            goodConditions2[i] = semantic.logicSystem.and(goodConditions2[i], allCondition.negated);

            goodConditionsStrict2[i] = semantic.logicSystem.and(goodConditionsStrict2[i], extraConditions[i]);
            goodConditions2[i] = semantic.logicSystem.and(goodConditions2[i], extraConditions[i]);

            if (mergeDepth == 1)
            {
                immutable(Formula)* extraConditionElse = semantic.logicSystem.true_;
                foreach (j; 0 .. tree.childs.length)
                    if (i != j)
                        extraConditionElse = semantic.logicSystem.and(extraConditionElse, extraConditions[j].negated);

                goodConditionsStrict2[i] = semantic.logicSystem.or(goodConditionsStrict2[i], extraConditionElse);
                goodConditions2[i] = semantic.logicSystem.or(goodConditions2[i], extraConditionElse);
            }
        }

        foreach (i; 0 .. tree.childs.length)
        {
            if (mergeDepth == 1)
            {
                mdata.conditions[i] = semantic.logicSystem.or(mdata.conditions[i],
                        semantic.logicSystem.or(goodConditionsStrict2[i], goodConditions2[i]));
            }
            resultGoodConditionStrict = semantic.logicSystem.or(resultGoodConditionStrict,
                    goodConditionsStrict2[i]);
            resultGoodCondition = semantic.logicSystem.or(resultGoodCondition,
                    goodConditionsStrict2[i]);
            resultGoodCondition = semantic.logicSystem.or(resultGoodCondition, goodConditions2[i]);
            badCondition = semantic.logicSystem.and(badCondition, goodConditionsStrict2[i].negated);
            badCondition = semantic.logicSystem.and(badCondition, goodConditions2[i].negated);
        }

        if (defaultTree != size_t.max)
        {
            if (mergeDepth == 1)
            {
                immutable(Formula)* badCondition2 = badCondition;
                badCondition2 = semantic.logicSystem.and(badCondition2, extraConditions[defaultTree]);

                mdata.conditions[defaultTree] = semantic.logicSystem.or(
                        mdata.conditions[defaultTree], badCondition2);
            }
            resultGoodConditionStrict = semantic.logicSystem.or(resultGoodConditionStrict,
                    semantic.logicSystem.and(badCondition, defaultConditionStrict));
            resultGoodCondition = semantic.logicSystem.or(resultGoodCondition, semantic.logicSystem.and(badCondition, defaultCondition));
            badCondition = semantic.logicSystem.false_;
        }

        if (contextType !is null)
        {
            QualType combinedType;
            foreach (i, ref c; tree.childs)
            {
                combinedType = combineTypes(combinedType, childContextTypes[i],
                        null, mdata.conditions[i], semantic);
            }
            *contextType = combinedType;
        }

        if (mergeDepth == 1)
            mdata.mergedCondition = semantic.logicSystem.or(mdata.mergedCondition, badCondition);

        goodConditionStrict = semantic.logicSystem.and(resultGoodConditionStrict, goodConditionStrict);
        goodCondition = resultGoodCondition;
    }
    else if (tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
    {
        auto ctree = tree.toConditionTree;
        assert(ctree !is null);

        immutable(Formula)* combinedConditionStrict = semantic.logicSystem.false_;
        immutable(Formula)* combinedCondition = semantic.logicSystem.false_;
        immutable(Formula)* origIsDependentName = isDependentName ? *isDependentName : semantic.logicSystem.false_;
        foreach (i; 0 .. ctree.childs.length)
        {
            immutable(Formula)* isDependentName2 = origIsDependentName;
            immutable(Formula)* goodConditionStrict2 = semantic.logicSystem.and(
                    goodConditionStrict, ctree.conditions[i]);
            immutable(Formula)* goodCondition2 = semantic.logicSystem.and(goodCondition,
                    ctree.conditions[i]);
            handleConflictExpression(ctree.childs[i], goodConditionStrict2,
                    goodCondition2, semantic, flags, null, &isDependentName2);
            tree.childs[i] = ctree.childs[i];
            combinedCondition = semantic.logicSystem.or(combinedCondition, goodCondition2);
            combinedConditionStrict = semantic.logicSystem.or(combinedConditionStrict,
                    goodConditionStrict2);
            if (isDependentName)
            {
                *isDependentName = semantic.logicSystem.or(*isDependentName, semantic.logicSystem.and(isDependentName2, ctree.conditions[i]));
            }
        }
        goodCondition = combinedCondition;
        goodConditionStrict = combinedConditionStrict;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ArrayDeclarator")
    {
        handleConflictExpression(tree.childs[2], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"InitializerClause")
    {
        handleConflictExpression(tree.childs[$ - 1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].content == "sizeof" && tree.childs.length == 4)
    {
        // "sizeof" "(" TypeId ")"

        foreach (i, ref c; tree.childs)
        {
            ConflictExpressionFlags flags2 = ConflictExpressionFlags.none;
            if (i == 2)
                flags2 |= ConflictExpressionFlags.inType;
            handleConflictExpression(c, goodConditionStrict, goodCondition, semantic, flags2);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].content == "sizeof" && tree.childs.length == 2)
    {
        // "sizeof" UnaryExpression

        foreach (i, ref c; tree.childs)
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition,
                    semantic, ConflictExpressionFlags.none);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"CastExpressionHead")
    {
        foreach (i, ref c; tree.childs)
        {
            ConflictExpressionFlags flags2 = ConflictExpressionFlags.none;
            if (i == 1)
                flags2 |= ConflictExpressionFlags.inType;
            handleConflictExpression(c, goodConditionStrict, goodCondition, semantic, flags2);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"PrimaryExpression"
            && tree.childs[0].content == "(")
    {
        foreach (i, ref c; tree.childs)
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition,
                    semantic, ConflictExpressionFlags.none);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"PostfixExpression"
            && tree.childs.length == 4 && tree.childs[0].nodeType == NodeType.nonterminal
            && tree.childs[1].content == "(")
    {
        foreach (i, ref c; tree.childs[0 .. 1])
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition,
                    semantic, ConflictExpressionFlags.inCall);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnqualifiedId" && tree.childs[0].content == "~")
    {
        foreach (i, ref c; tree.childs)
        {
            ConflictExpressionFlags flags2 = ConflictExpressionFlags.none;
            if (i == 1)
                flags2 |= ConflictExpressionFlags.inType;
            handleConflictExpression(c, goodConditionStrict, goodCondition, semantic, flags2);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnaryExpression"
            && tree.childs[0].nodeType == NodeType.token
            && tree.childs[0].content == "~")
    {
        foreach (i, ref c; tree.childs)
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition,
                    semantic, ConflictExpressionFlags.none);
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"PostfixExpression"
            && tree.childs.length == 4 && tree.childs[1].content.among("->", "."))
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
        if (tree.childs[3].nonterminalID == nonterminalIDFor!"SimpleTemplateId")
        {
            goodConditionStrict = semantic.logicSystem.false_;
            goodCondition = semantic.logicSystem.false_;
        }
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NameIdentifier")
    {
        assert(tree.childs.length == 1);
        assert(tree.childs[0].nodeType == NodeType.token);
        string name = tree.childs[0].content;

        immutable(Formula)* combinedCondition = semantic.logicSystem.false_;
        QualType combinedType;
        foreach (combination; iterateCombinations())
        {
            IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                    goodConditionStrict, semantic.instanceCondition, semantic.mergedTreeDatas);

            Type recordType;
            if (contextType !is null)
            {
                recordType = recordTypeFromType(ppVersion, semantic, *contextType);
                if ((*contextType).type !is null && recordType is null)
                    continue;
            }

            Scope scope_ = semantic.currentScope;
            if (recordType !is null)
            {
                scope_ = scopeForRecord(recordType, ppVersion, semantic);
            }

            if (isDependentName && (flags & ConflictExpressionFlags.inType) && isInCorrectVersion(ppVersion, *isDependentName))
            {
                goodCondition = semantic.logicSystem.and(goodCondition, ppVersion.condition.negated);
                continue;
            }

            Declaration[] ds = lookupName(name, scope_, ppVersion,
                    LookupNameFlags.followForwardScopes | LookupNameFlags.strictCondition);

            bool isDecl, isNotDecl, isTemplate;
            foreach (d; ds)
            {
                if (!isInCorrectVersion(ppVersion, d.condition))
                    continue;
                immutable(Formula)* condition = ppVersion.logicSystem.and(ppVersion.condition,
                        d.condition);
                if (d.type.among(DeclarationType.type, DeclarationType.namespace))
                    isDecl = true;
                if (d.type == DeclarationType.varOrFunc)
                    isNotDecl = true;
                if (d.flags & DeclarationFlags.template_)
                    isTemplate = true;
                if ((d.flags & DeclarationFlags.templateParam) && isDependentName)
                    *isDependentName = ppVersion.logicSystem.or(*isDependentName, ppVersion.condition);

                QualType type2 = d.declaredType;
                if (type2.type is null)
                    type2 = d.type2;
                if (d.type == DeclarationType.type)
                    type2.qualifiers |= Qualifiers.noThis;
                combinedType = combineTypes(combinedType, type2, null,
                        semantic.logicSystem.and(condition, ppVersion.condition), semantic);
            }
            if ((flags & ConflictExpressionFlags.inTemplate) && !isTemplate)
                continue;
            else if ((flags & ConflictExpressionFlags.notTemplate) && isTemplate)
                continue;
            else if (flags & ConflictExpressionFlags.inType)
            {
                if (isDecl && !isNotDecl)
                    combinedCondition = semantic.logicSystem.or(combinedCondition,
                            ppVersion.condition);
            }
            else
            {
                if (isDecl && (flags & ConflictExpressionFlags.inCall)) // For Constructor call
                    isNotDecl = true;

                if ( /* !isDecl && */ isNotDecl)
                    combinedCondition = semantic.logicSystem.or(combinedCondition,
                            ppVersion.condition);
            }
        }
        goodConditionStrict = combinedCondition;
        if (contextType !is null)
            *contextType = combinedType;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"QualifiedId" && tree.childs.length == 3)
    {
        immutable(Formula)* isDependentName2 = semantic.logicSystem.false_;
        immutable(Formula)* origGoodConditionStrict = goodConditionStrict;
        goodConditionStrict = goodCondition;
        scope (exit)
            goodConditionStrict = semantic.logicSystem.and(goodConditionStrict,
                    origGoodConditionStrict);

        QualType contextType2;
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none, &contextType2, &isDependentName2);
        handleConflictExpression(tree.childs[$ - 1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none, &contextType2, &isDependentName2);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NestedNameSpecifier")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType, contextType, isDependentName);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"NestedNameSpecifierHead")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType, contextType);
        handleConflictExpression(tree.childs[$ - 1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType, contextType);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"SimpleTemplateId")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict, goodCondition,
                semantic, flags | ConflictExpressionFlags.inTemplate, contextType, isDependentName);
        handleConflictExpression(tree.childs[2], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none, null, isDependentName);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"SimpleTypeSpecifierNoKeyword")
    {
        immutable(Formula)* isDependentName2 = semantic.logicSystem.false_;
        immutable(Formula)* origGoodConditionStrict = goodConditionStrict;
        goodConditionStrict = goodCondition;
        scope (exit)
            goodConditionStrict = semantic.logicSystem.and(goodConditionStrict,
                    origGoodConditionStrict);

        QualType contextType2;
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType, &contextType2, &isDependentName2);
        handleConflictExpression(tree.childs[$ - 1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType, &contextType2, &isDependentName2);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"EnumeratorInitializer")
    {
        handleConflictExpression(tree.childs[1], goodConditionStrict,
                goodCondition, semantic, flags);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"TemplateName")
    {
        goodConditionStrict = semantic.logicSystem.false_;
        goodCondition = semantic.logicSystem.false_;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"TypenameSpecifier" && !(flags & ConflictExpressionFlags.inType))
    {
        goodConditionStrict = semantic.logicSystem.false_;
        goodCondition = semantic.logicSystem.false_;
    }
    else if (tree.nonterminalID == nonterminalIDFor!"UnqualifiedId" && tree.childs[0].content == "~")
    {
        goodConditionStrict = semantic.logicSystem.false_;
        goodCondition = semantic.logicSystem.false_;
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("TypeId"))
    {
        assert(tree.childs[0].nodeType == NodeType.array);
        immutable(Formula)* isDependentName2 = semantic.logicSystem.false_;
        if (tree.childs[0].childs.length == 0)
        {
            goodConditionStrict = semantic.logicSystem.false_;
            goodCondition = semantic.logicSystem.false_;
        }
        else
        {
            foreach (i, ref c; tree.childs)
            {
                handleConflictExpression(c, goodConditionStrict, goodCondition,
                        semantic, ConflictExpressionFlags.inType, null, &isDependentName2);
            }
        }
    }
    else if (tree.name.endsWith("RelationalExpression")
            && tree.childs[1].content == "<")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.notTemplate);
        goodCondition = goodConditionStrict;
        handleConflictExpression(tree.childs[2], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.name.endsWith("MultiplicativeExpression")
            && tree.childs[1].content == "*")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
        goodCondition = goodConditionStrict;
        handleConflictExpression(tree.childs[2], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.name.endsWith("UnaryExpression") && tree.childs[0].content == "*")
    {
        goodCondition = goodConditionStrict;
        handleConflictExpression(tree.childs[1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"FunctionDefinitionHead")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType);
        handleConflictExpression(tree.childs[1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"SimpleDeclaration1" && tree.childs.length == 3)
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.inType);
        handleConflictExpression(tree.childs[1], goodConditionStrict,
                goodCondition, semantic, ConflictExpressionFlags.none);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"DeclSpecifierSeq")
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, flags);
    }
    else if (tree.nonterminalID.nonterminalIDAmong!("FunctionDeclarator", "NoptrDeclarator"))
    {
        handleConflictExpression(tree.childByName("innerDeclarator"),
                goodConditionStrict, goodCondition, semantic, flags);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"DeclaratorId")
    {
        QualType contextType2;
        if (tree.hasChildWithName("nestedName"))
            handleConflictExpression(tree.childByName("nestedName"),
                    goodConditionStrict, goodCondition, semantic, flags, &contextType2);
        handleConflictExpression(tree.childs[$ - 1], goodConditionStrict,
                goodCondition, semantic, flags, &contextType2);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"Statement" && tree.childs.length == 2)
    {
        handleConflictExpression(tree.childs[1], goodConditionStrict,
                goodCondition, semantic, flags);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"ExpressionStatement" && tree.childs.length == 2)
    {
        handleConflictExpression(tree.childs[0], goodConditionStrict,
                goodCondition, semantic, flags);
    }
    else if (tree.nonterminalID == nonterminalIDFor!"StaticAssertDeclarationX")
    {
        handleConflictExpression(tree.childs[2], goodConditionStrict,
                goodCondition, semantic, flags);
    }
    else if (tree.name.endsWith("Expression"))
    {
        foreach (i, ref c; tree.childs)
        {
            handleConflictExpression(c, goodConditionStrict, goodCondition,
                    semantic, ConflictExpressionFlags.none);
        }
    }
}

void classParents(ref Appender!(RecordType[]) parents, Declaration d,
        ref IteratePPVersions ppVersion, Semantic semantic, bool recursive)
{
    if (!d.tree.isValid || d.tree.name != "ClassSpecifier")
        return;
    Tree classHead = ppVersion.chooseTree(d.tree.childs[0]);
    Tree baseClause = ppVersion.chooseTree(classHead.childs[$ - 1]);
    if (!baseClause.isValid)
        return;

    void analyzeTree(Tree tree)
    {
        tree = ppVersion.chooseTree(tree);
        if (!tree.isValid)
            return;
        if (tree.nodeType == NodeType.array)
        {
            foreach (c; tree.childs)
                analyzeTree(c);
        }
        else if (tree.nodeType == NodeType.nonterminal)
        {
            assert(tree.nonterminalID == ParserWrapper.nonterminalIDFor!"BaseSpecifier");
            Tree baseTypeSpecifier = ppVersion.chooseTree(tree.childs[$ - 1]);
            auto type = chooseType(semantic.extraInfo(baseTypeSpecifier).type, ppVersion, true);
            if (type.kind == TypeKind.record)
            {
                auto recordType = cast(RecordType) type.type;
                if (!parents.data.canFind(recordType))
                {
                    parents.put(recordType);
                    if (recursive)
                        classParents(parents, recordType, ppVersion, semantic, recursive);
                }
            }
        }
    }

    analyzeTree(baseClause.childs[1]);
}

void classParents(ref Appender!(RecordType[]) parents, RecordType type,
        ref IteratePPVersions ppVersion, Semantic semantic, bool recursive)
{
    foreach (e; type.declarationSet.entries)
    {
        if (e.data.type == DeclarationType.forwardScope)
            continue;
        if ((e.data.flags & DeclarationFlags.typedef_) != 0)
            continue;
        if (e.data.type == DeclarationType.namespace)
            continue;
        if (!isInCorrectVersion(ppVersion, e.condition))
            continue;
        bool hasRealDecl;
        foreach (e2; e.data.realDeclaration.entries)
        {
            if (ppVersion.logicSystem.and(e2.condition, ppVersion.condition).isFalse)
                continue;
            if (isInCorrectVersion(ppVersion, e2.condition))
            {
                classParents(parents, e2.data, ppVersion, semantic, recursive);
                hasRealDecl = true;
            }
        }
        if (!hasRealDecl)
            classParents(parents, e.data, ppVersion, semantic, recursive);
    }
}

Scope scopeForRecord(Type type, ref IteratePPVersions ppVersion, Semantic semantic)
{
    Declaration[] declarations;
    DeclarationSet declarationSet;
    if (type.kind == TypeKind.record)
        declarationSet = (cast(RecordType) type).declarationSet;
    else if (type.kind == TypeKind.namespace)
    {
        declarationSet = (cast(NamespaceType) type).declarationSet;
        if (declarationSet is null)
            return semantic.rootScope;
    }
    else
        assert(false);

    foreach (e; declarationSet.entries)
    {
        if (e.data.type == DeclarationType.forwardScope)
            continue;
        if ((e.data.flags & DeclarationFlags.typedef_) != 0)
            continue;
        if (e.data.flags & DeclarationFlags.templateSpecialization)
            continue;
        if (type.kind == TypeKind.namespace && e.data.type != DeclarationType.namespace)
            continue;
        if (type.kind != TypeKind.namespace && e.data.type == DeclarationType.namespace)
            continue;
        if (ppVersion.logicSystem.and(e.condition, ppVersion.condition).isFalse)
            continue;
        immutable(Formula)* conditionAnyRealDecl = ppVersion.logicSystem.false_;
        foreach (e2; e.data.realDeclaration.entries)
        {
            if (e2.data.flags & DeclarationFlags.templateSpecialization)
                continue;
            if (ppVersion.logicSystem.and(e2.condition,
                    ppVersion.logicSystem.and(e.condition, ppVersion.condition)).isFalse)
                continue;
            conditionAnyRealDecl = ppVersion.logicSystem.or(conditionAnyRealDecl, e2.condition);
            declarations.addOnce(e2.data);
        }
        if (!ppVersion.logicSystem.and(conditionAnyRealDecl.negated, ppVersion.condition).isFalse)
            declarations.addOnce(e.data);
    }
    Scope scope_;
    if (declarations.length)
    {
        size_t chosen = ppVersion.combination.next(cast(uint) declarations.length);
        auto d = declarations[chosen];
        ppVersion.condition = ppVersion.logicSystem.and(ppVersion.condition, d.condition);

        if (type.kind == TypeKind.namespace)
            scope_ = d.scope_.childNamespaces[declarationSet.name];
        else if (d.tree in d.scope_.childScopeByTree)
            scope_ = d.scope_.childScopeByTree[d.tree];
        else
            scope_ = null;
    }
    else
    {
        scope_ = null;
    }
    return scope_;
}

Tree findWrappingDeclaration(Tree tree, Semantic semantic)
{
    Tree wrapperDeclaration = tree;
    while (true)
    {
        Tree p = getRealParent(wrapperDeclaration, semantic);
        if (p.isValid && (p.name.startsWith("SimpleDeclaration") || p.name.startsWith("MemberDeclaration")
                || p.nonterminalID.nonterminalIDAmong!("DeclSpecifierSeq", "FunctionDefinitionHead",
                "ParameterDeclaration", "ParameterDeclarationAbstract", "Condition")))
        {
            wrapperDeclaration = p;
            continue;
        }
        break;
    }
    return wrapperDeclaration;
}

template iterateTreeConditions(alias F)
{
    static if (is(typeof(F) Params == __parameters))
        auto iterateTreeConditions(Params allParams)
        {
            alias R = typeof(F(allParams));
            if (!tree.isValid)
            {
                static if (is(R == void))
                    return;
                else
                    return R.init;
            }
            if (condition.isFalse)
                return;

            if (tree.nodeType == NodeType.nonterminal
                    && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID)
            {
                auto ctree = tree.toConditionTree;
                assert(ctree !is null);

                foreach (i; 0 .. ctree.childs.length)
                {
                    auto subTreeCondition = ctree.conditions[i];
                    static if (is(typeof(allParams[2]) == SemanticRunInfo))
                    {
                        if (semantic.instanceCondition !is null)
                            subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                                    semantic.instanceCondition, semantic.logicSystem);
                    }
                    else
                        static assert(is(typeof(allParams[2]) == Semantic));

                    iterateTreeConditions!(F)(ctree.childs[i],
                            semantic.logicSystem.and(subTreeCondition,
                                condition), semantic, allParams[3 .. $]);
                }
            }
            else if (tree.nodeType == NodeType.merged && tree.nodeType == NodeType.merged)
            {
                auto mdata = &semantic.mergedTreeData(tree);

                foreach (i; 0 .. tree.childs.length)
                {
                    auto subTreeCondition = mdata.conditions[i];
                    static if (is(typeof(allParams[2]) == SemanticRunInfo))
                    {
                        if (semantic.instanceCondition !is null)
                            subTreeCondition = replaceIncludeInstanceCondition(subTreeCondition,
                                    semantic.instanceCondition, semantic.logicSystem);
                    }
                    else
                        static assert(is(typeof(allParams[2]) == Semantic));

                    auto condition2 = semantic.logicSystem.and(semantic.logicSystem.or(subTreeCondition,
                            semantic.logicSystem.and(mdata.mergedCondition,
                            semantic.logicSystem.literal("#merged"))), condition);
                    iterateTreeConditions!(F)(tree.childs[i], condition2,
                            semantic, allParams[3 .. $]);
                }
            }
            else
            {
                return F(tree, condition, semantic, allParams[3 .. $]);
            }
        }
}

string fullyQualifiedName(Semantic semantic, Declaration d)
{
    auto inCache = d in semantic.fullyQualifiedNameCache;
    if (inCache)
        return *inCache;
    Appender!string app;
    void visitScope(Scope s)
    {
        if (s is null)
            return;
        if (s.parentScope !is null)
            visitScope(s.parentScope);

        if (s.tree.isValid)
        {
            string name2;
            auto declarations = semantic.extraInfo(findWrappingDeclaration(s.tree,
                semantic)).declarations;
            foreach (d2; declarations)
            {
                if (name2 != "" && d2.name != name2)
                    name2 = "??";
                else
                    name2 = d2.name;
            }
            if (name2 != "")
                app.put(name2 ~ "::");
            else if(s.tree.nonterminalID == nonterminalIDFor!"TemplateDeclaration")
                app.put("template param::");
            else if(s.tree.nonterminalID == nonterminalIDFor!"ParametersAndQualifiers")
                app.put("function param::");
        }
        else if (s.parentScope is null)
        {
        }
        else
            app.put(s.className.entries[0].data ~ "::");
    }

    Scope s = d.scope_;
    if (d.tree.isValid && d.tree.nodeType != NodeType.token
        && (d.tree.name.startsWith("FunctionDefinition")
            || d.tree.nonterminalID == nonterminalIDFor!"ClassSpecifier")
        && d.tree in d.scope_.childScopeByTree)
    {
        Scope s2 = d.scope_.childScopeByTree[d.tree];
        foreach (e; s2.extraParentScopes.entries)
        {
            if (e.data.type == ExtraScopeType.namespace)
                s = e.data.scope_;
        }
    }
    visitScope(s);
    if (app.data.length == 0)
    {
        semantic.fullyQualifiedNameCache[d] = d.name;
        return d.name;
    }
    app.put(d.name);
    semantic.fullyQualifiedNameCache[d] = app.data;
    return app.data;
}
