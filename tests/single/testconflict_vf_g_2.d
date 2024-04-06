
module testconflict_vf_g_2;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias x = int;
}
static if (!defined!"DEF")
{
__gshared const(int) x = 0;
}

__gshared const(int) y = 1;

static if (defined!"DEF")
{
int f(x*  y__1);
}
static if (!defined!"DEF")
{
__gshared auto f = int(x*y);
}

