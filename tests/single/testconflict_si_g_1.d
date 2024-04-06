module testconflict_si_g_1;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
__gshared int i;
}
static if (!defined!"DEF")
{
alias i = int;
}

__gshared const(int) s = mixin((!defined!"DEF") ? q{
        cast(const(int)) (i.sizeof)
    } : q{
        cast(const(int)) ((i). sizeof)
    });

