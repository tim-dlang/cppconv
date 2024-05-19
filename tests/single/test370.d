
module test370;

import config;
import cppconvhelpers;
import qt.core.metatype;

struct QMetaTypeId(T)
{
}

/+ #define Q_DECLARE_METATYPE(TYPE) Q_DECLARE_METATYPE_IMPL(TYPE)
#define Q_DECLARE_METATYPE_IMPL(TYPE)                                   \
    template <>                                                         \
    struct QMetaTypeId< TYPE >                                          \
    {                                                                   \
        enum { Defined = 1 };                                           \
        static int qt_metatype_id()                                     \
            {                                                           \
                return 1;                                           \
            }                                                           \
    }; +/


@Q_DECLARE_METATYPE struct S
{
}
/+ Q_DECLARE_METATYPE(S); +/

