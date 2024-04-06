module test326;

import config;
import cppconvhelpers;


void f(T)()
{
static assert(bool(!QMetaTypeId2!(T).IsBuiltIn), "");
static assert(!QMetaTypeId2!(T).IsBuiltIn || QMetaTypeId2!(T).IsBuiltIn, "");
}

struct QMetaTypeId2(T)
{
    enum { IsBuiltIn=false }
}

/+ template <typename T>
struct QMetaTypeId2<const T&> : QMetaTypeId2<T> {};

template <typename T>
struct QMetaTypeId2<T&> { enum {Defined = false }; }; +/

