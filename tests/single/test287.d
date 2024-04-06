module test287;

import config;
import cppconvhelpers;

/+ #define QT_DEPRECATED_X(x)
#undef Q_QDOC

#ifdef Q_QDOC
typedef void* LessThan;
template <typename T> LessThan qLess();
template <typename T> LessThan qGreater();
#else +/
extern(C++, class) struct /+ QT_DEPRECATED_X("Use std::less") +/ qLess(T)
{
public:
    /+pragma(inline, true) bool operator ()(ref const(T) t1, ref const(T) t2) const
    {
        return (t1 < t2);
    }+/
}
/+ #endif +/

