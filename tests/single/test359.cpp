#ifdef ALWAYS_PREDEFINED_IN_TEST
# define QT_ANNOTATE_ACCESS_SPECIFIER(x) __cppconv_##x
#else
# define QT_ANNOTATE_ACCESS_SPECIFIER(x)
#endif
# define Q_SIGNALS public QT_ANNOTATE_ACCESS_SPECIFIER(qt_signal)

struct QSignal{}; // UDA

class C1
{
    int x;
#ifdef DEF
    void f();
#endif
Q_SIGNALS:
    void g();
};

class C2
{
#ifdef DEF
    void f();
#endif
Q_SIGNALS:
    void g();
};
