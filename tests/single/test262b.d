
module test262b;

import config;
import cppconvhelpers;

const(char)* qFlagLocation(const(char)* method);

/+ #define QT_STRINGIFY2(x) #x +/
extern(D) alias QT_STRINGIFY2 = function string(string x)
{
    return mixin(interpolateMixin(q{$(stringifyMacroParameter(x))}));
};
/+ #define QT_STRINGIFY(x) QT_STRINGIFY2(x) +/
extern(D) alias QT_STRINGIFY = function string(string x)
{
    return mixin(interpolateMixin(q{$(imported!q{test262b}.QT_STRINGIFY2(q{$(stringifyMacroParameter(x))}))}));
};

/+ # define QT_STRINGIFY_SIGNAL(a) "2" #a +/
extern(D) alias QT_STRINGIFY_SIGNAL = function string(string a)
{
    return mixin(interpolateMixin(q{"2" ~ $(stringifyMacroParameter(a))}));
};

static if (!defined!"QT_NO_DEBUG")
{
/+ #  define QLOCATION "\0" __FILE__ ":" QT_STRINGIFY(__LINE__) +/
enum QLOCATION = "\0" ~ __FILE__ ~ ":" ~ mixin(QT_STRINGIFY(q{__LINE__}));
/+ #  define SLOT(a)     qFlagLocation("1"#a QLOCATION) +/
extern(D) alias SLOT = function string(string a)
{
    return     mixin(interpolateMixin(q{imported!q{test262b}.qFlagLocation("1"~ $(stringifyMacroParameter(a))~ imported!q{test262b}.QLOCATION)}));
};
/+ #  define SIGNAL(a)   qFlagLocation(QT_STRINGIFY_SIGNAL(a) QLOCATION) +/
extern(D) alias SIGNAL = function string(string a)
{
    return   mixin(interpolateMixin(q{imported!q{test262b}.qFlagLocation($(imported!q{test262b}.QT_STRINGIFY_SIGNAL(q{$(stringifyMacroParameter(a))})) ~ imported!q{test262b}.QLOCATION)}));
};
}
static if (defined!"QT_NO_DEBUG")
{
/+ #  define SLOT(a)     "1"#a +/
extern(D) alias SLOT = function string(string a)
{
    return     mixin(interpolateMixin(q{"1"~ $(stringifyMacroParameter(a))}));
};
/+ #  define SIGNAL(a)   QT_STRINGIFY_SIGNAL(a) +/
extern(D) alias SIGNAL = function string(string a)
{
    return   mixin(interpolateMixin(q{$(imported!q{test262b}.QT_STRINGIFY_SIGNAL(q{$(stringifyMacroParameter(a))}))}));
};
}

extern(C++, class) struct QObject
{
public:
    static void connect(const(QObject)* sender, const(char)* signal,
                            const(QObject)* receiver, const(char)* member);
}

void f(QObject* a, QObject* b)
{
	QObject.connect(a, mixin(SIGNAL(q{signalVoid()})), b, mixin(SLOT(q{onSignalVoid()})));
}

