module testdefines12;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
/+ #define A 1 +/
enum A = 1;
}
static if (!defined!"DEF")
{
/+ #define A 2 +/
enum A = 2;
}

/+ #define f(x) (x) +/
extern(D) alias f = function string(string x)
{
    return mixin(interpolateMixin(q{($(x))}));
};

__gshared int x = mixin(f(q{mixin((defined!"DEF") ? q{
                A
            } : q{
            A
            })}));
__gshared int y = 3* mixin(f(q{4+ mixin((defined!"DEF") ? q{
                A
            } : q{
            A
            })+5}));

