template <typename T>
struct QMetaTypeId2;

template <typename T>
void f()
{
static_assert(bool(!QMetaTypeId2<T>::IsBuiltIn), "");
static_assert(!QMetaTypeId2<T>::IsBuiltIn || QMetaTypeId2<T>::IsBuiltIn, "");
}

template <typename T>
struct QMetaTypeId2
{
    enum { IsBuiltIn=false };
};

template <typename T>
struct QMetaTypeId2<const T&> : QMetaTypeId2<T> {};

template <typename T>
struct QMetaTypeId2<T&> { enum {Defined = false }; };
