
template <typename T>
struct QMetaTypeId
{
};

#define Q_DECLARE_METATYPE(TYPE) Q_DECLARE_METATYPE_IMPL(TYPE)
#define Q_DECLARE_METATYPE_IMPL(TYPE)                                   \
    template <>                                                         \
    struct QMetaTypeId< TYPE >                                          \
    {                                                                   \
        enum { Defined = 1 };                                           \
        static int qt_metatype_id()                                     \
            {                                                           \
                return 1;                                           \
            }                                                           \
    };


struct S
{
};
Q_DECLARE_METATYPE(S);
