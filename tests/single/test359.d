module test359;

import config;
import cppconvhelpers;

/+ #ifdef ALWAYS_PREDEFINED_IN_TEST
# define QT_ANNOTATE_ACCESS_SPECIFIER(x) __cppconv_##x
#else
# define QT_ANNOTATE_ACCESS_SPECIFIER(x)
#endif
# define Q_SIGNALS public QT_ANNOTATE_ACCESS_SPECIFIER(qt_signal) +/

struct QSignal{} // UDA

extern(C++, class) struct C1
{
private:
    int x;
    static if (defined!"DEF")
    {
        void f();
    }
/+ Q_SIGNALS +/public:
    @QSignal void g();
}

extern(C++, class) struct C2
{
private:
    static if (defined!"DEF")
    {
        void f();
    }
/+ Q_SIGNALS +/public:
    @QSignal void g();
}

