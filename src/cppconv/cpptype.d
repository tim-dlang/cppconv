
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cpptype;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.logic;
import cppconv.mergedfile;
import cppconv.runcppcommon;
import cppconv.utils;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.typecons;

enum IntegralCategory
{
    int_,
    char_,
    size,
    float_
}

struct IntegralInfo
{
    string name;
    IntegralCategory category;
    bool isUnsigned;
    byte sizeOrder; // Orders types by size, but is not the exact size
}

// https://en.cppreference.com/w/cpp/language/types
immutable integralInfos = [
    // always 8 Bit
    IntegralInfo("char", IntegralCategory.char_, false, 1),
    IntegralInfo("int8", IntegralCategory.int_, false, 1),
    IntegralInfo("unsigned_int8", IntegralCategory.int_, true, 1),
    IntegralInfo("signed_char", IntegralCategory.int_, false, 1),
    IntegralInfo("unsigned_char", IntegralCategory.int_, true, 1),

    // always 16 Bit
    IntegralInfo("char16", IntegralCategory.char_, false, 2),
    IntegralInfo("int16", IntegralCategory.int_, false, 2),
    IntegralInfo("unsigned_int16", IntegralCategory.int_, true, 2),
    IntegralInfo("short", IntegralCategory.int_, false, 2),
    IntegralInfo("unsigned_short", IntegralCategory.int_, true, 2),

    // 16 bit (windows) or 32 bit
    IntegralInfo("wchar", IntegralCategory.char_, false, 3),

    // always 32 bit
    IntegralInfo("char32", IntegralCategory.char_, false, 4),
    IntegralInfo("int32", IntegralCategory.int_, false, 4),
    IntegralInfo("unsigned_int32", IntegralCategory.int_, true, 4),

    // 16 - 64 bit, but assume >= 32 bit
    IntegralInfo("int", IntegralCategory.int_, false, 5),
    IntegralInfo("unsigned", IntegralCategory.int_, true, 5),
    IntegralInfo("ptrdiff", IntegralCategory.size, false, 5),
    IntegralInfo("ssize", IntegralCategory.size, false, 5),
    IntegralInfo("size", IntegralCategory.size, true, 5),
    IntegralInfo("intptr", IntegralCategory.size, false, 5),
    IntegralInfo("uintptr", IntegralCategory.size, true, 5),

    // 32 - 64 bit
    IntegralInfo("long", IntegralCategory.int_, false, 6),
    IntegralInfo("unsigned_long", IntegralCategory.int_, true, 6),

    // always 64 bit
    IntegralInfo("int64", IntegralCategory.int_, false, 7),
    IntegralInfo("unsigned_int64", IntegralCategory.int_, true, 7),
    IntegralInfo("long_long", IntegralCategory.int_, false, 7),
    IntegralInfo("unsigned_long_long", IntegralCategory.int_, true, 7),

    IntegralInfo("intmax", IntegralCategory.int_, false, 8),
    IntegralInfo("uintmax", IntegralCategory.int_, true, 8),

    IntegralInfo("float", IntegralCategory.float_, false, 5),
    IntegralInfo("double", IntegralCategory.float_, false, 7),
];

IntegralInfo getIntegralInfo(string name)
{
    foreach (info; integralInfos)
        if (info.name == name)
            return info;
    return IntegralInfo.init;
}

enum TypeKind
{
    none,
    condition,
    builtin,
    typedef_,
    array,
    pointer,
    reference,
    rValueReference,
    record,
    function_,
    namespace
}

abstract class Type
{
    immutable TypeKind kind;

    protected this(TypeKind kind)
    {
        this.kind = kind;
    }

    inout(QualType[]) allNext() inout
    {
        return [];
    }

    string name() const
    {
        return "";
    }
}

class ConditionType : Type
{
    QualType[] types;
    immutable(Formula*)[] conditions;
    this()
    {
        super(TypeKind.condition);
    }

    override inout(QualType[]) allNext() inout
    {
        return types;
    }
}

class BuiltinType : Type
{
    string name_;
    this()
    {
        super(TypeKind.builtin);
    }

    override string name() const
    {
        return name_;
    }
}

class RecordType : Type
{
    DeclarationSet declarationSet;
    QualType[] next;
    this()
    {
        super(TypeKind.record);
    }

    protected this(TypeKind kind)
    {
        super(kind);
    }

    override inout(QualType[]) allNext() inout
    {
        return next;
    }

    override string name() const
    {
        return declarationSet.name;
    }
}

class TypedefType : RecordType
{
    QualType realType;
    this()
    {
        super(TypeKind.typedef_);
    }

    override inout(QualType[]) allNext() inout
    {
        return next ~ realType;
    }
}

class FunctionType : Type
{
    QualType resultType;
    QualType[] parameters;
    bool isVariadic;
    bool isConst;
    bool isRef;
    bool isRValueRef;
    size_t neededParameters;
    this()
    {
        super(TypeKind.function_);
    }

    override inout(QualType[]) allNext() inout
    {
        return (&resultType)[0 .. 1] ~ parameters;
    }
}

class ArrayType : Type
{
    QualType next;
    Tree declarator;
    this()
    {
        super(TypeKind.array);
    }

    override inout(QualType[]) allNext() inout
    {
        return (&next)[0 .. 1];
    }
}

class PointerType : Type
{
    QualType next;
    this()
    {
        super(TypeKind.pointer);
    }

    override inout(QualType[]) allNext() inout
    {
        return (&next)[0 .. 1];
    }
}

class ReferenceType : Type
{
    QualType next;
    this()
    {
        super(TypeKind.reference);
    }

    override inout(QualType[]) allNext() inout
    {
        return (&next)[0 .. 1];
    }
}

class RValueReferenceType : Type
{
    QualType next;
    this()
    {
        super(TypeKind.rValueReference);
    }

    override inout(QualType[]) allNext() inout
    {
        return (&next)[0 .. 1];
    }
}

class NamespaceType : Type
{
    DeclarationSet declarationSet;
    this()
    {
        super(TypeKind.namespace);
    }

    override string name() const
    {
        return declarationSet is null ? "" : declarationSet.name;
    }
}

enum Qualifiers
{
    none = 0,
    const_ = 1,
    volatile_ = 2,
    restrict_ = 4,
    noThis = 8
}

struct QualType
{
    Type type;
    Qualifiers qualifiers;

    this(Type t, Qualifiers qualifiers = Qualifiers.none)
    {
        this.type = t;
        this.qualifiers = qualifiers;
    }

    this(QualType t, Qualifiers qualifiers = Qualifiers.none)
    {
        this.type = t.type;
        this.qualifiers = t.qualifiers | qualifiers;
    }

    TypeKind kind() const
    {
        if (type is null)
            return TypeKind.none;
        else
            return type.kind;
    }

    auto name()
    {
        if (type is null)
            return "";
        else
            return type.name;
    }

    auto allNext()
    {
        return type.allNext;
    }

    QualType withExtraQualifiers(Qualifiers qualifiers)
    {
        return QualType(type, this.qualifiers | qualifiers);
    }
}

string typeToString(const QualType type)
{
    if (type.type is null)
        return "nulltype";

    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        string r = "ConditionType" /*~ "@" ~ text(cast(void*)(ctype))*/  ~ "(";

        foreach (i, c; ctype.types)
        {
            if (i)
                r ~= ", ";
            r ~= ctype.conditions[i].toString ~ " => " ~ typeToString(c);
        }
        r ~= ")";
        return r;
    }

    string line = text(type.kind) ~ " " ~ type.type.name /*~ "@" ~ text(cast(void*)(type.type))*/ ;
    if (type.qualifiers & Qualifiers.const_)
        line ~= " const";
    if (type.qualifiers & Qualifiers.volatile_)
        line ~= " volatile";
    if (type.qualifiers & Qualifiers.restrict_)
        line ~= " restrict";
    if (type.qualifiers & Qualifiers.noThis)
        line ~= " noThis";

    if (type.kind == TypeKind.record)
    {
        RecordType rtype = cast(RecordType) type.type;
        line ~= " " ~ rtype.declarationSet.scope_.toString;
    }
    line ~= "(";
    foreach (i, c; type.type.allNext)
    {
        if (i)
            line ~= ", ";
        line ~= typeToString(c);
    }
    if (type.kind == TypeKind.function_)
    {
        FunctionType ftype = cast(FunctionType) type.type;
        if (ftype.isVariadic)
            line ~= ", ...";
    }
    line ~= ")";
    if (type.kind == TypeKind.function_)
    {
        FunctionType ftype = cast(FunctionType) type.type;
        if (ftype.isConst)
            line ~= " const";
        if (ftype.isRef)
            line ~= " &";
        if (ftype.isRValueRef)
            line ~= " &&";
    }
    return line;
}

Type tryMergeTypes(Type type1, Type type2, immutable(Formula)* condition1,
        immutable(Formula)* condition2, Semantic semantic)
{
    if (type1 is null || type2 is null)
        return null;
    if (type1.kind != type2.kind)
        return null;

    auto typeApp = stackArrayAllocator!QualType;

    static string buildCode()
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

            code ~= "if (type1.kind == TypeKind." ~ kind ~ ")\n";
            code ~= "{\n";

            if (kindU == "Condition")
            {
                code ~= "return null;";
                code ~= "}\n";
                continue;
            }

            code ~= kindU ~ "Type xtype1 = cast(" ~ kindU ~ "Type)type1;\n";
            code ~= kindU ~ "Type xtype2 = cast(" ~ kindU ~ "Type)type2;\n";

            foreach (name; FieldNameTupleAll!T)
            {
                alias T2 = typeof(__traits(getMember, T, name));

                static if (is(T2 == QualType))
                {
                }
                else static if (is(T2 == QualType[]))
                {
                    code ~= "if (xtype1." ~ name ~ ".length != xtype2." ~ name ~ ".length)\n";
                    code ~= "{\n";
                    code ~= "    return null;\n";
                    code ~= "}\n";
                    static if (false)
                    {
                        code ~= "foreach (i; 0..xtype1." ~ name ~ ".length)\n";
                        code ~= "    if (xtype1." ~ name ~ "[i] != xtype2." ~ name ~ "[i])";
                        code ~= "        return null;\n";
                    }
                    else static if (false)
                    {
                        code ~= "size_t numDifferent;\n";
                        code ~= "foreach (i; 0..xtype1." ~ name ~ ".length)\n";
                        code ~= "    if (filterType(xtype1." ~ name
                            ~ "[i], condition1, semantic) != filterType(xtype2."
                            ~ name ~ "[i], condition2, semantic))";
                        code ~= "    {\n";
                        code ~= "        numDifferent++;\n";
                        code ~= "        if (numDifferent >= 2)\n";
                        code ~= "            return null;\n";
                        code ~= "    }\n";
                    }
                }
                else
                {
                    code ~= "if (xtype1." ~ name ~ " != xtype2." ~ name ~ ")\n";
                    code ~= "{\n";
                    code ~= "    return null;\n";
                    code ~= "}\n";
                }
            }

            code ~= "return semantic.get" ~ kindU ~ "Type(";

            foreach (name; FieldNameTupleAll!T)
            {
                alias T2 = typeof(__traits(getMember, T, name));

                static if (is(T2 == QualType))
                {
                    code ~= "combineTypes(xtype1." ~ name ~ ", xtype2." ~ name
                        ~ ", condition1, condition2, semantic), ";
                }
                else static if (is(T2 == QualType[]))
                {
                    code ~= "(){";
                    code ~= "foreach (i;0..xtype1." ~ name ~ ".length) typeApp.put(QualType());";
                    code ~= "QualType[] r = typeApp.data[$-xtype1." ~ name ~ ".length..$];";
                    code ~= "foreach (i, ref x; r) x = combineTypes(xtype1." ~ name
                        ~ "[i], xtype2." ~ name ~ "[i], condition1, condition2, semantic);";
                    code ~= "return r;";
                    code ~= "}(), ";
                }
                else
                {
                    code ~= "xtype1." ~ name ~ ", ";
                }
            }

            code ~= ");\n";

            code ~= "}\n";
        }
        return code;
    }

    mixin(buildCode());
    assert(false);
}

enum FilterTypeFlags
{
    none,
    removeTypedef = 1,
    replaceRealTypes = 2,
    simplifyFunctionType = 4,
    fakeTemplateScope = 8,
}

QualType filterType(QualType type, immutable(Formula)* condition,
        Semantic semantic, FilterTypeFlags flags = FilterTypeFlags.none)
{
    if (type.type is null)
        return type;

    auto typeApp = stackArrayAllocator!QualType;
    auto conditionApp = stackArrayAllocator!(immutable(Formula)*);

    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        QualType[] types2 = typeApp.getN(ctype.types.length);
        immutable(Formula)*[] conditions2 = conditionApp.getN(ctype.types.length);
        bool changed = false;
        size_t k;
        foreach (i; 0 .. ctype.types.length)
        {
            immutable(Formula)* condition2 = semantic.logicSystem.and(condition,
                    ctype.conditions[i]);
            if (condition2.isFalse)
            {
                changed = true;
                continue;
            }
            auto filtered = filterType(ctype.types[i], condition2, semantic, flags);
            if (filtered != ctype.types[i])
                changed = true;
            types2[k] = filtered;

            auto condition3 = semantic.logicSystem.removeRedundant(condition2, condition);
            conditions2[k] = condition3;
            if (condition3 !is condition2)
                changed = true;
            k++;
        }
        types2 = types2[0 .. k];
        conditions2 = conditions2[0 .. k];
        if (types2.length == 1)
            return types2[0].withExtraQualifiers(type.qualifiers);
        if (!changed)
            return type;
        auto r = QualType(semantic.getConditionType(types2,
                cast(immutable(Formula*)[]) conditions2), type.qualifiers);
        if ((cast(ConditionType) r.type).types.length == 1)
            return (cast(ConditionType) r.type).types[0].withExtraQualifiers(r.qualifiers);
        return r;
    }

    if ((flags & (FilterTypeFlags.replaceRealTypes | FilterTypeFlags.fakeTemplateScope)) != 0
            && type.kind.among(TypeKind.record))
    {
        auto recordType = cast(RecordType) type.type;
        QualType combinedType = type;

        foreach (i; 0 .. recordType.next.length)
            typeApp.put(QualType());
        QualType[] next = typeApp.data[$ - recordType.next.length .. $];
        foreach (i, ref x; next)
            x = filterType(recordType.next[i], condition, semantic, flags);

        auto typeApp2 = stackArrayAllocator!QualType;
        auto conditionApp2 = stackArrayAllocator!(immutable(Formula)*);

        DeclarationSet moveToFakeTemplateScope(DeclarationSet ds)
        {
            if (flags & FilterTypeFlags.fakeTemplateScope)
            {
                if (!ds.scope_.tree.isValid)
                    return ds;
                if (ds.scope_.tree.name != "TemplateDeclaration")
                    return ds;

                if (semantic.fakeTemplateScope is null)
                {
                    semantic.fakeTemplateScope = new Scope(Tree.init, null);
                }

                return semantic.fakeTemplateScope.getDeclarationSet(ds.name, semantic.logicSystem);
            }
            else
                return ds;
        }

        immutable(Formula)* conditionLeft = condition;
        foreach (e; recordType.declarationSet.entries)
        {
            if (e.data.type != DeclarationType.type)
                continue;
            if ((e.data.flags & DeclarationFlags.typedef_) != 0)
                continue;
            if (flags & FilterTypeFlags.replaceRealTypes)
            {
                foreach (e2; e.data.realDeclaration.entries)
                {
                    auto condition2 = semantic.logicSystem.and(condition,
                            semantic.logicSystem.and(e.condition, e2.condition));
                    if (condition2.isFalse)
                        continue;

                    auto t2 = QualType(semantic.getRecordType(moveToFakeTemplateScope(e2.data.declarationSet),
                            next), type.qualifiers);
                    typeApp2.put(t2);
                    conditionApp2.put(condition2);
                    conditionLeft = semantic.logicSystem.and(conditionLeft, condition2.negated);
                }
            }
        }
        if (!conditionLeft.isFalse)
        {
            if (flags & FilterTypeFlags.fakeTemplateScope)
            {
                auto t2 = QualType(semantic.getRecordType(moveToFakeTemplateScope(recordType.declarationSet),
                        next), type.qualifiers);
                typeApp2.put(t2);
                conditionApp2.put(conditionLeft);
            }
            else
            {
                auto t2 = QualType(semantic.getRecordType(recordType.declarationSet,
                        next), type.qualifiers);
                typeApp2.put(t2);
                conditionApp2.put(conditionLeft);
            }
        }

        auto r = semantic.getConditionType(typeApp2.data, conditionApp2.data);
        if (r.kind == TypeKind.condition)
        {
            auto conditionType = cast(ConditionType) r.type;
            if (conditionType.conditions.length == 1)
            {
                return conditionType.types[0].withExtraQualifiers(r.qualifiers);
            }
        }
        return r;
    }

    QualType[] filterChilds(QualType[] types)
    {
        foreach (i; 0 .. types.length)
            typeApp.put(QualType());
        QualType[] r = typeApp.data[$ - types.length .. $];
        foreach (i, ref x; r)
            x = filterType(types[i], condition, semantic, flags);
        return r;
    }

    if ((flags & FilterTypeFlags.simplifyFunctionType) != 0 && type.kind.among(TypeKind.function_))
    {
        auto functionType = cast(FunctionType) type.type;
        return QualType(semantic.getFunctionType(filterType(functionType.resultType, condition, semantic, flags),
                filterChilds(functionType.parameters), functionType.isVariadic, functionType.isConst,
                functionType.isRef, functionType.isRValueRef, functionType.parameters.length),
                type.qualifiers);
    }

    static string buildCode()
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

            if (kindU == "Condition")
            {
                continue;
            }

            code ~= "if (type.kind == TypeKind." ~ kind ~ ")\n";
            code ~= "{\n";

            code ~= kindU ~ "Type xtype = cast(" ~ kindU ~ "Type)type.type;\n";

            if (kindU == "Typedef")
                code ~= "if (flags & FilterTypeFlags.removeTypedef) return filterType(xtype.realType, condition, semantic, flags).withExtraQualifiers(type.qualifiers);\n";

            code ~= "return QualType(semantic.get" ~ kindU ~ "Type(";

            foreach (name; FieldNameTupleAll!T)
            {
                alias T2 = typeof(__traits(getMember, T, name));

                static if (is(T2 == QualType))
                {
                    code ~= "filterType(xtype." ~ name ~ ", condition, semantic, flags), ";
                }
                else static if (is(T2 == QualType[]))
                {
                    code ~= "filterChilds(xtype." ~ name ~ "), ";
                }
                else
                {
                    code ~= "xtype." ~ name ~ ", ";
                }
            }

            code ~= "), type.qualifiers);\n";

            code ~= "}\n";
        }
        return code;
    }

    mixin(buildCode());
    assert(false);
}

QualType combineTypes(QualType type1, QualType type2, immutable(Formula)* condition1,
        immutable(Formula)* condition2, Semantic semantic,
        string filename = __FILE__, size_t line = __LINE__)
{
    immutable(Formula)* allCondition = semantic.logicSystem.true_;
    if (condition1 is null)
        condition1 = condition2.negated;
    else
        allCondition = semantic.logicSystem.or(condition1, condition2);
    if (type1.type is null && type2.type is null)
    {
        return QualType(null);
    }

    if (type1 == type2)
        return type1;

    auto typeApp = stackArrayAllocator!QualType;
    auto conditionApp = stackArrayAllocator!(immutable(Formula)*);

    ConditionType ctype1;
    ConditionType ctype2;
    size_t length1;
    if (type1.type is null)
    {
        length1 = 0;
    }
    else if (type1.kind == TypeKind.condition)
    {
        ctype1 = cast(ConditionType) type1.type;
        length1 = ctype1.types.length;
    }
    else
    {
        length1 = 1;
    }

    size_t length2;
    if (type2.type !is null && type2.kind == TypeKind.condition)
    {
        ctype2 = cast(ConditionType) type2.type;
        length2 = ctype2.types.length;
    }
    else
    {
        length2 = 1;
    }

    QualType[] typesAll = typeApp.getN(length1 + length2);
    immutable(Formula)*[] conditionsAll = conditionApp.getN(length1 + length2);

    QualType[] types1;
    immutable(Formula)*[] conditions1;
    QualType[] types2;
    immutable(Formula)*[] conditions2;

    types1 = typesAll[0 .. length1];
    types2 = typesAll[length1 .. length1 + length2];
    conditions1 = conditionsAll[0 .. length1];
    conditions2 = conditionsAll[length1 .. length1 + length2];

    if (type1.type is null)
    {
    }
    else if (type1.kind == TypeKind.condition)
    {
        foreach (i; 0 .. types1.length)
        {
            types1[i] = ctype1.types[i];
            conditions1[i] = ctype1.conditions[i];
            types1[i].qualifiers |= type1.qualifiers;
            conditions1[i] = semantic.logicSystem.and(conditions1[i], condition1);
            //if (!semantic.logicSystem.and(conditions1[i].negated, condition1).isFalse)
            types1[i] = filterType(types1[i], conditions1[i], semantic);
        }
    }
    else
    {
        types1[0] = filterType(type1, condition1, semantic);
        conditions1[0] = condition2.negated;
    }

    if (type2.type !is null && type2.kind == TypeKind.condition)
    {
        foreach (i; 0 .. types2.length)
        {
            types2[i] = ctype2.types[i];
            conditions2[i] = ctype2.conditions[i];
            types2[i].qualifiers |= type2.qualifiers;
            conditions2[i] = semantic.logicSystem.and(conditions2[i], condition2);
            //if (!semantic.logicSystem.and(conditions2[i].negated, condition2).isFalse)
            types2[i] = filterType(types2[i], conditions2[i], semantic);
        }
    }
    else
    {
        types2[0] = filterType(type2, condition2, semantic);
        conditions2[0] = condition2;
    }

    outer: foreach (i; 0 .. types2.length)
    {
        foreach (k; 0 .. types1.length)
        {
            QualType merged;
            if (types1[k].qualifiers == types2[i].qualifiers)
                merged = QualType(tryMergeTypes(types1[k].type, types2[i].type,
                        conditions1[k], conditions2[i], semantic), types1[k].qualifiers);

            if (merged.type !is null || (types1[k].type is null && types2[i].type is null))
            {
                conditions1[k] = semantic.logicSystem.or(conditions1[k], conditions2[i]);
                types1[k] = merged;
                continue outer;
            }
        }
        types1 = typesAll[0 .. types1.length + 1];
        types1[$ - 1] = types2[i];
        conditions1 = conditionsAll[0 .. conditions1.length + 1];
        conditions1[$ - 1] = conditions2[i];
    }

    if (types1.length == 1 && semantic.logicSystem.and(allCondition,
            conditions1[0].negated).isFalse && types1[0].type !is null)
        return types1[0];

    foreach (ref c; conditions1)
    {
        c = semantic.logicSystem.removeRedundant(c, allCondition);
        c = simplifyMergedCondition(c, semantic.logicSystem);
    }

    auto r = QualType(semantic.getConditionType(types1,
            cast(immutable(Formula*)[]) conditions1), Qualifiers.none);
    return r;
}

QualType evaluateType(alias F)(QualType type)
{
    if (type.type is null)
        return type;
    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        foreach (i; 0 .. ctype.types.length)
        {
            if (ctype.conditions[i].boundEvaluate!F())
                return evaluateType!F(QualType(ctype.types[i].type,
                        ctype.types[i].qualifiers | type.qualifiers));
        }
        return QualType.init;
    }
    return type;
}

immutable(Formula)* typeKindIs(Type type, TypeKind kind, LogicSystem logicSystem,
        bool followTypedef = true)
{
    if (type is null)
        return logicSystem.false_;
    if (type.kind == TypeKind.condition)
    {
        immutable(Formula)* r = logicSystem.false_;
        auto ctype = cast(ConditionType) type;
        foreach (i; 0 .. ctype.types.length)
        {
            r = logicSystem.or(r, logicSystem.and(ctype.conditions[i],
                    typeKindIs(ctype.types[i].type, kind, logicSystem, followTypedef)));
        }
        return r;
    }

    if (followTypedef && type.kind == TypeKind.typedef_)
    {
        auto t2 = cast(TypedefType) type;
        return typeKindIs(t2.realType.type, kind, logicSystem, followTypedef);
    }

    if (type.kind == kind)
        return logicSystem.true_;
    else
        return logicSystem.false_;
}

QualType chooseType(QualType type, ref IteratePPVersions ppVersion, bool followTypedef)
{
    while (type.type !is null)
    {
        if (type.kind == TypeKind.condition)
        {
            auto ctype = cast(ConditionType) type.type;
            size_t numPossible;
            foreach (i; 0 .. ctype.conditions.length)
            {
                if (!ppVersion.logicSystem.and(ppVersion.condition, ctype.conditions[i]).isFalse)
                    numPossible++;
            }
            if (numPossible == 0)
                return QualType();
            size_t chosen = ppVersion.combination.next(cast(uint) numPossible);
            size_t index;
            foreach (i; 0 .. ctype.conditions.length)
            {
                if (!ppVersion.logicSystem.and(ppVersion.condition, ctype.conditions[i]).isFalse)
                {
                    if (index == chosen)
                    {
                        ppVersion.condition = ppVersion.logicSystem.and(ppVersion.condition,
                                ctype.conditions[i]);
                        type = ctype.types[i].withExtraQualifiers(type.qualifiers);
                        break;
                    }
                    index++;
                }
            }
        }
        else if (followTypedef && type.kind == TypeKind.typedef_)
        {
            auto ttype = cast(TypedefType) type.type;
            QualType realType = chooseType(ttype.realType, ppVersion, followTypedef);
            if (realType.type is null)
                break;
            type = realType.withExtraQualifiers(type.qualifiers);
        }
        else
            break;
    }
    return type;
}

bool isTemplateParamType(Type type)
{
    if (type.kind != TypeKind.record)
        return false;
    auto recordType = cast(RecordType) type;
    if (recordType.declarationSet.scope_ is null)
        return false;
    if (!recordType.declarationSet.scope_.tree.isValid)
        return false;
    return recordType.declarationSet.scope_.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"TemplateDeclaration";
}

bool needsCast(QualType toType, QualType fromType, ref IteratePPVersions ppVersion,
        Semantic semantic)
{
    toType = chooseType(toType, ppVersion, true);
    fromType = chooseType(fromType, ppVersion, true);
    if (toType.type is null || fromType.type is null)
        return false;

    if (toType.kind == TypeKind.reference)
    {
        toType = (cast(ReferenceType) toType.type).next.withExtraQualifiers(toType.qualifiers);
    }
    if (fromType.kind == TypeKind.reference)
    {
        fromType = (cast(ReferenceType) fromType.type).next.withExtraQualifiers(
                fromType.qualifiers);
    }

    if (toType.kind == TypeKind.builtin && toType.name == "auto")
        return false;

    if (fromType.kind.among(TypeKind.pointer, TypeKind.array)
            && toType.kind.among(TypeKind.pointer, TypeKind.array))
    {
        if ((fromType.qualifiers | toType.qualifiers) != toType.qualifiers)
            return true;
        auto fromTypeNext = fromType.type.allNext()[0];
        auto toTypeNext = toType.type.allNext()[0];
        if (toType.kind == TypeKind.array && fromType.kind == TypeKind.array)
            fromTypeNext = QualType(fromTypeNext.type); // allow implicit cast to non-const
        return needsCastPointee(toTypeNext, fromTypeNext, ppVersion, semantic);
    }

    if (fromType.kind == TypeKind.record && toType.kind == TypeKind.builtin)
    {
        auto fromType2 = cast(RecordType) fromType.type;
        auto toType2 = cast(BuiltinType) toType.type;

        immutable(Formula)* isEnum = ppVersion.logicSystem.false_;
        foreach (e; fromType2.declarationSet.entries)
        {
            if (e.data.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EnumSpecifier")
                isEnum = ppVersion.logicSystem.or(isEnum,
                        ppVersion.logicSystem.and(ppVersion.condition, e.condition));
        }

        auto toInfo = getIntegralInfo(toType2.name);

        if (isInCorrectVersion(ppVersion, isEnum))
        {
            if (toInfo.sizeOrder < getIntegralInfo("unsigned").sizeOrder)
                return true;
            return false;
        }
    }
    if (isTemplateParamType(fromType.type))
        return false;
    if (isTemplateParamType(toType.type))
        return false;
    if (fromType.kind == TypeKind.builtin && toType.kind == TypeKind.pointer)
    {
        auto fromType2 = cast(BuiltinType) fromType.type;
        auto toType2 = cast(PointerType) toType.type;
        if (fromType2.name == "null")
            return false;
    }

    if (fromType.kind == TypeKind.builtin && toType.kind == TypeKind.builtin)
    {
        auto fromType2 = cast(BuiltinType) fromType.type;
        auto toType2 = cast(BuiltinType) toType.type;

        auto toInfo = getIntegralInfo(toType2.name);
        auto fromInfo = getIntegralInfo(fromType2.name);

        if (toType2.name != fromType2.name && toInfo.name && fromInfo.name)
        {
            if (toInfo.category == IntegralCategory.float_)
                return false;
            if (fromInfo.category == IntegralCategory.float_)
                return true;
            if (toInfo.sizeOrder < fromInfo.sizeOrder)
                return true;
        }
    }

    if (fromType.kind != toType.kind)
        return true;

    return false;
}

bool needsCastPointee(QualType toType, QualType fromType,
        ref IteratePPVersions ppVersion, Semantic semantic)
{
    toType = chooseType(toType, ppVersion, true);
    fromType = chooseType(fromType, ppVersion, true);
    if (toType.type is null || fromType.type is null)
        return false;
    if (toType.kind == TypeKind.typedef_)
        return needsCastPointee((cast(TypedefType) toType.type)
                .realType.withExtraQualifiers(toType.qualifiers), fromType, ppVersion, semantic);
    if (fromType.kind == TypeKind.typedef_)
        return needsCastPointee(toType, (cast(TypedefType) fromType.type)
                .realType.withExtraQualifiers(fromType.qualifiers), ppVersion, semantic);

    if ((fromType.qualifiers | toType.qualifiers) != toType.qualifiers)
        return true;

    if (toType.type is fromType.type)
        return false;

    if (fromType.kind != TypeKind.builtin && toType.kind == TypeKind.builtin)
    {
        auto toType2 = cast(BuiltinType) toType.type;
        if (toType2.name == "void")
            return false;
    }
    if (fromType.kind == TypeKind.builtin && toType.kind == TypeKind.builtin)
    {
        auto fromType2 = cast(BuiltinType) fromType.type;
        auto toType2 = cast(BuiltinType) toType.type;
        if (fromType2.name == "void" && toType2.name != "void")
            return true;
        if (fromType2.name != "void" && toType2.name == "void")
            return false;
    }

    if (fromType.kind == TypeKind.function_ && toType.kind == TypeKind.function_)
    {
        auto fromType2 = cast(FunctionType) fromType.type;
        auto toType2 = cast(FunctionType) toType.type;
        return fromType2.resultType !is toType2.resultType || fromType2.parameters != toType2.parameters
            || fromType2.isConst != toType2.isConst || fromType2.isVariadic != toType2.isVariadic;
    }

    if (fromType.kind == TypeKind.record && toType.kind == TypeKind.record)
    {
        auto fromType2 = cast(RecordType) fromType.type;
        auto toType2 = cast(RecordType) toType.type;

        if (isTemplateParamType(fromType2) || isTemplateParamType(toType2))
            return false;

        Appender!(RecordType[]) parents;
        classParents(parents, fromType2, ppVersion, semantic, true);
        if (parents.data.canFind(toType2))
            return false;
    }

    if (fromType.kind != toType.kind)
        return true;

    return true;
}

bool isPossiblyEnumType(QualType t)
{
    if (t.kind != TypeKind.record)
        return false;
    auto recordType = cast(RecordType) t.type;
    foreach (e; recordType.declarationSet.entries)
    {
        if (e.data.type != DeclarationType.type)
            continue;
        if (e.data.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"EnumSpecifier")
            return true;
        if (e.data.tree.nonterminalID == ParserWrapper.nonterminalIDFor!"ElaboratedTypeSpecifier"
                && e.data.tree.childs[0].nameOrContent == "enum")
            return true;
    }
    return false;
}

void getImplicitConstructTypes(QualType t, ref Appender!(QualType[]) types,
        ref IteratePPVersions ppVersion, Semantic semantic)
{
    if (types.data.canFind(t))
        return;
    types.put(t);

    if (t.kind == TypeKind.record)
    {
        Scope s = scopeForRecord(t.type, ppVersion, semantic);
        if (s !is null)
        {
            auto ds = "$norettype:" ~ t.name in s.symbols;
            if (ds)
            {
                foreach (e; ds.entries)
                {
                    auto ftype = chooseType(e.data.type2, ppVersion, true);
                    if (ftype.kind == TypeKind.function_)
                    {
                        auto functionType = cast(FunctionType) ftype.type;
                        if (functionType.parameters.length == 1 && !functionType.isVariadic)
                        {
                            QualType ptype = chooseType(functionType.parameters[0], ppVersion, true);
                            if (ptype.kind == TypeKind.reference)
                            {
                                ptype = (cast(ReferenceType) ptype.type).next.withExtraQualifiers(
                                        ptype.qualifiers);
                            }
                            getImplicitConstructTypes(ptype, types, ppVersion, semantic);
                        }
                    }
                }
            }
        }
    }
}

bool isSameType(QualType toType, QualType fromType,
        ref IteratePPVersions ppVersion, Semantic semantic)
{
    toType = chooseType(toType, ppVersion, true);
    fromType = chooseType(fromType, ppVersion, true);

    if (toType.type is null || fromType.type is null)
        return false;

    if (toType.kind == TypeKind.reference)
    {
        toType = (cast(ReferenceType) toType.type).next.withExtraQualifiers(toType.qualifiers);
    }
    if (fromType.kind == TypeKind.reference)
    {
        fromType = (cast(ReferenceType) fromType.type).next.withExtraQualifiers(
                fromType.qualifiers);
    }
    return toType.type is fromType.type;
}

// Return true if unknown.
bool isImplicitConversionPossible(QualType toType, QualType fromType,
        ref IteratePPVersions ppVersion, Semantic semantic)
{
    toType = chooseType(toType, ppVersion, true);
    fromType = chooseType(fromType, ppVersion, true);

    if (toType.type is null || fromType.type is null)
        return true;

    if (toType.kind == TypeKind.reference)
    {
        toType = (cast(ReferenceType) toType.type).next.withExtraQualifiers(toType.qualifiers);
    }
    if (fromType.kind == TypeKind.reference)
    {
        fromType = (cast(ReferenceType) fromType.type).next.withExtraQualifiers(
                fromType.qualifiers);
    }

    if (fromType.kind == TypeKind.record && toType.kind == TypeKind.builtin
            && !isTemplateParamType(fromType.type))
    {
        if (isPossiblyEnumType(fromType))
            return true;
        return false;
    }
    if (fromType.kind == TypeKind.record && toType.kind == TypeKind.record
            && !isTemplateParamType(toType.type) && !isTemplateParamType(fromType.type))
    {
        if (isPossiblyEnumType(toType))
            return true;
        if (isPossiblyEnumType(fromType))
            return true;

        Appender!(QualType[]) implicitTypes;
        getImplicitConstructTypes(toType, implicitTypes, ppVersion, semantic);
        foreach (t; implicitTypes.data)
        {
            if (fromType.type is t.type)
                return true;
        }

        return false;
    }
    if (fromType.kind.among(TypeKind.builtin, TypeKind.pointer, TypeKind.array)
            && toType.kind == TypeKind.record && !isTemplateParamType(toType.type))
    {
        if (isPossiblyEnumType(toType))
            return true;

        Appender!(QualType[]) implicitTypes;
        getImplicitConstructTypes(toType, implicitTypes, ppVersion, semantic);
        foreach (t; implicitTypes.data)
        {
            if (t.kind == TypeKind.builtin && t.name == "bool"
                    && fromType.kind == TypeKind.builtin && fromType.name.among("double", "float"))
                continue;
            if (t.kind.among(TypeKind.builtin, TypeKind.pointer, TypeKind.array))
                return true;
        }

        return false;
    }

    return true;
}

QualType createCommonType(QualType t1, QualType t2,
        ref IteratePPVersions ppVersion, Semantic semantic, bool isResult)
{
    if (t1 == t2)
        return t1;
    Qualifiers combineQualifiers(Qualifiers q1, Qualifiers q2)
    {
        if (isResult)
            return t1.qualifiers & t2.qualifiers;
        else
            return t1.qualifiers | t2.qualifiers;
    }

    if (t1.type is t2.type)
    {
        return QualType(t1.type, combineQualifiers(t1.qualifiers, t2.qualifiers));
    }

    QualType t1x = chooseType(t1, ppVersion, false);
    QualType t2x = chooseType(t2, ppVersion, false);

    if (t1x.kind == TypeKind.typedef_ && t2x.kind == TypeKind.typedef_)
    {
        auto typedefType1 = cast(TypedefType) t1x.type;
        auto typedefType2 = cast(TypedefType) t2x.type;
        if (typedefType1.declarationSet is typedefType2.declarationSet
                && typedefType1.next.length == 0 && typedefType2.next.length == 0)
        {
            auto next = createCommonType(typedefType1.realType,
                    typedefType2.realType, ppVersion, semantic, isResult);
            auto typedefType = semantic.getTypedefType(typedefType1.declarationSet, [], next);
            return QualType(typedefType, combineQualifiers(t1.qualifiers, t2.qualifiers));
        }
    }

    t1x = chooseType(t1x, ppVersion, true);
    t2x = chooseType(t2x, ppVersion, true);
    if (t1x.type is t2x.type)
    {
        return QualType(t1x.type, combineQualifiers(t1x.qualifiers, t2x.qualifiers));
    }

    if (t1x.kind.among(TypeKind.pointer, TypeKind.array)
            && t2x.kind.among(TypeKind.pointer, TypeKind.array))
    {
        auto next = createCommonType(t1x.allNext()[0], t2x.allNext()[0],
                ppVersion, semantic, isResult);
        auto r = semantic.getPointerType(next);
        return QualType(r, combineQualifiers(t1x.qualifiers, t2x.qualifiers));
    }
    if (t1x.kind.among(TypeKind.reference) && t2x.kind.among(TypeKind.reference))
    {
        auto next = createCommonType(t1x.allNext()[0], t2x.allNext()[0],
                ppVersion, semantic, isResult);
        auto r = semantic.getReferenceType(next);
        return QualType(r, combineQualifiers(t1x.qualifiers, t2x.qualifiers));
    }

    if (t1x.kind == TypeKind.function_ && t2x.kind == TypeKind.function_)
    {
        auto functionType1 = cast(FunctionType) t1x.type;
        auto functionType2 = cast(FunctionType) t2x.type;

        auto resultType = createCommonType(functionType1.resultType,
                functionType2.resultType, ppVersion, semantic, isResult);
        QualType[] parameters;
        parameters.length = min(functionType1.parameters.length, functionType2.parameters.length);
        foreach (i; 0 .. parameters.length)
            parameters[i] = createCommonType(functionType1.parameters[i],
                    functionType2.parameters[i], ppVersion, semantic, isResult);

        bool isVariadic = functionType1.isVariadic || functionType2.isVariadic;
        bool isConst = functionType1.isConst || functionType2.isConst;
        bool isRef = functionType1.isRef || functionType2.isRef;
        bool isRValueRef = functionType1.isRValueRef || functionType2.isRValueRef;
        size_t neededParameters = min(functionType1.neededParameters,
                functionType2.neededParameters);

        auto r = semantic.getFunctionType(resultType, parameters, isVariadic,
                isConst, isRef, isRValueRef, neededParameters);
        return QualType(r, combineQualifiers(t1x.qualifiers, t2x.qualifiers));
    }

    if (t1x.kind == TypeKind.builtin && t2x.kind == TypeKind.builtin)
    {
        if (t1x.name == "float" && t2x.name == "double")
        {
            return QualType(isResult ? t1x.type : t2x.type,
                    combineQualifiers(t1x.qualifiers, t2x.qualifiers));
        }
        if (t1x.name == "double" && t2x.name == "float")
        {
            return QualType(isResult ? t2x.type : t1x.type,
                    combineQualifiers(t1x.qualifiers, t2x.qualifiers));
        }
    }

    return QualType.init;
}

QualType functionResultType(QualType type, Semantic semantic)
{
    QualType combinedType;
    foreach (combination; iterateCombinations())
    {
        IteratePPVersions ppVersion = IteratePPVersions(combination, semantic.logicSystem,
                semantic.logicSystem.true_, null, semantic.mergedTreeDatas);
        auto t = chooseType(type, ppVersion, true);

        if (t.qualifiers & Qualifiers.noThis && t.kind != TypeKind.function_)
        {
            combinedType = combineTypes(combinedType, t, null, ppVersion.condition, semantic);
        }
        else
        {
            if (t.type !is null && t.kind == TypeKind.pointer)
                t = t.allNext()[0];

            QualType r;

            if (t.type !is null && t.kind == TypeKind.function_)
                r = (cast(FunctionType) t.type).resultType;

            combinedType = combineTypes(combinedType, r, null, ppVersion.condition, semantic);
        }
    }

    return combinedType;
}

QualType arrayTypeToPointer(QualType type, immutable(Formula*) condition,
        immutable(Formula*) contextCondition, Semantic semantic)
{
    if (type.type is null)
        return type;
    QualType[] types;
    immutable(Formula)*[] conditions;
    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        types = ctype.types.dup;
        conditions = ctype.conditions.dup;
    }
    else
    {
        types = [type];
        conditions = [contextCondition];
    }
    foreach (i; 0 .. types.length)
    {
        if (types[i].type !is null && types[i].kind == TypeKind.array)
        {
            auto atype = cast(ArrayType) types[i].type;
            if (semantic.logicSystem.and(contextCondition,
                    semantic.logicSystem.and(conditions[i], condition.negated)).isFalse)
            {
                types[i] = QualType(semantic.getPointerType(atype.next), types[i].qualifiers);
            }
            else
            {
                types ~= QualType(semantic.getPointerType(atype.next), types[i].qualifiers);
                conditions ~= semantic.logicSystem.and(contextCondition,
                        semantic.logicSystem.and(conditions[i], condition));
                conditions[i] = semantic.logicSystem.and(contextCondition,
                        semantic.logicSystem.and(conditions[i], condition.negated));
            }
        }
    }
    return QualType(semantic.getConditionType(types, conditions.idup), type.qualifiers);
}

QualType commonType(QualType type1, QualType type2,
        ref IteratePPVersions ppVersion, Semantic semantic)
{
    type1 = chooseType(type1, ppVersion, true);
    type2 = chooseType(type2, ppVersion, true);

    if (type1.type is null || type2.type is null)
        return QualType();

    if (type1.type is type2.type)
        return QualType(type1.type, type1.qualifiers | type2.qualifiers);

    if (type1.kind == TypeKind.pointer && type2.kind == TypeKind.pointer)
    {
        auto next1 = chooseType(type1.type.allNext()[0], ppVersion, true);
        auto next2 = chooseType(type2.type.allNext()[0], ppVersion, true);
        if (next1.type !is null && next1.kind == TypeKind.builtin && next1.name == "void")
            return QualType(type1.type, type1.qualifiers | type2.qualifiers);
        if (next2.type !is null && next2.kind == TypeKind.builtin && next2.name == "void")
            return QualType(type2.type, type1.qualifiers | type2.qualifiers);
    }

    return QualType();
}

bool isConst(QualType type)
{
    if (type.type is null)
        return false;

    if ((type.qualifiers & Qualifiers.const_) != 0)
        return true;

    if (type.kind == TypeKind.condition)
    {
        auto ctype = cast(ConditionType) type.type;
        foreach (i; 0 .. ctype.types.length)
        {
            if (!isConst(ctype.types[i]))
                return false;
        }
        return true;
    }
    else if (type.kind == TypeKind.typedef_)
    {
        return isConst((cast(TypedefType) type.type).realType);
    }
    return false;
}

Type recordTypeFromType(ref IteratePPVersions ppVersion, Semantic semantic, QualType contextType)
{
    Type recordType;
    if (contextType.type !is null)
    {
        size_t numPointers;
        while (contextType.type !is null && (contextType.kind == TypeKind.condition
                || contextType.kind == TypeKind.reference || (contextType.kind.among(TypeKind.pointer,
                TypeKind.array) && numPointers == 0) || contextType.kind == TypeKind.typedef_))
        {
            if (contextType.kind == TypeKind.condition)
            {
                auto ctype = cast(ConditionType) contextType.type;
                uint chosen = ppVersion.combination.next(cast(uint) ctype.types.length);
                ppVersion.condition = semantic.logicSystem.and(ppVersion.condition,
                        ctype.conditions[chosen]);
                if (ppVersion.condition.isFalse)
                    contextType = QualType(null);
                else if (ctype.types[chosen].type is null)
                    contextType = QualType(null);
                else
                    contextType = QualType(ctype.types[chosen].type);
            }
            else if (contextType.kind == TypeKind.reference)
            {
                contextType = QualType((cast(ReferenceType) contextType.type).next.type);
            }
            else if (contextType.kind == TypeKind.pointer)
            {
                contextType = QualType((cast(PointerType) contextType.type).next.type);
                numPointers++;
            }
            else if (contextType.kind == TypeKind.array)
            {
                contextType = QualType((cast(ArrayType) contextType.type).next.type);
                numPointers++;
            }
            else if (contextType.kind == TypeKind.typedef_)
            {
                contextType = QualType((cast(TypedefType) contextType.type).realType.type);
            }
        }
        if (contextType.type !is null && contextType.kind.among(TypeKind.record,
                TypeKind.namespace))
        {
            recordType = (contextType.type);
        }
    }
    return recordType;
}

Type charTypeFromPrefix(string value, Semantic semantic)
{
    Type charType = semantic.getBuiltinType("char");
    if (value.startsWith("L"))
        charType = semantic.getBuiltinType("wchar"); //semantic.wcharType().type;
    else if (value.startsWith("u8"))
        charType = semantic.getBuiltinType("char");
    else if (value.startsWith("u"))
        charType = semantic.getBuiltinType("char16");
    else if (value.startsWith("U"))
        charType = semantic.getBuiltinType("char32");
    return charType;
}
