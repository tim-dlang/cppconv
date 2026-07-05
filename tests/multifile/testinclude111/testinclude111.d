module testinclude111;

import config;
import cppconvhelpers;

/+ #define M(x) x +/
template M(params...) if (params.length == 1)
{
    enum x = params[0];
    enum M = x;
}

__gshared const(int) i = M!(
    /+ #ifdef IN_A +/
    mixin((true) ? q{
                1
            } : q{
            /+ #else +/
            2
            })/+ #endif +/
);
/+ #define STRINGIFY(x) #x +/
extern(D) alias STRINGIFY = function string(string x)
{
    return mixin(interpolateMixin(q{$(stringifyMacroParameter(x))}));
};

__gshared const(char * ) str = mixin(STRINGIFY(
    /+ #ifdef IN_A +/
q{    A
    /+ #else +/
    B}
    /+ #endif +/
));

