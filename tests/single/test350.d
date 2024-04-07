module test350;

import config;
import cppconvhelpers;

/+ #define QT_FOR_EACH_STATIC_PRIMITIVE_TYPE(F)\
    F(Void, 43, void) \
    F(Bool, 1, bool) \
    F(Int, 2, int) \
    F(UInt, 3, uint) \
    F(LongLong, 4, qlonglong) \
    F(ULongLong, 5, qulonglong) \
    F(Double, 6, double) \
    F(Long, 32, long) \
    F(Short, 33, short) \
    F(Char, 34, char) \
    F(Char16, 56, char16_t) \
    F(Char32, 57, char32_t) \
    F(ULong, 35, ulong) \
    F(UShort, 36, ushort) \
    F(UChar, 37, uchar) \
    F(Float, 38, float) \
    F(SChar, 40, signed char) \
    F(Nullptr, 51, std::nullptr_t) \
    F(QCborSimpleType, 52, QCborSimpleType)

#define QT_FOR_EACH_STATIC_TYPE(F)\
    QT_FOR_EACH_STATIC_PRIMITIVE_TYPE(F)

#define QT_DEFINE_METATYPE_ID(TypeName, Id, Name) \
    TypeName = Id, +/

extern(C++, class) struct C
{
private:
    enum Type {
        /+ QT_FOR_EACH_STATIC_TYPE(QT_DEFINE_METATYPE_ID) +/
Void=43,Bool=1,Int=2,UInt=3,LongLong=4,ULongLong=5,Double=6,Long=32,Short=33,Char=34,Char16=56,Char32=57,ULong=35,UShort=36,UChar=37,Float=38,SChar=40,Nullptr=51,QCborSimpleType=52,
        Unknown_Type = 0,
    }
}

