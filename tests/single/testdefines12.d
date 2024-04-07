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
template f(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f = (x);
}

__gshared int x = f!(mixin((defined!"DEF") ? q{
                A
            } : q{
            A
            }));
__gshared int y = 3* f!(4+ mixin((defined!"DEF") ? q{
                A
            } : q{
            A
            })+5);

