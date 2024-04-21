module testconflict_vf_g_8;

import config;
import cppconvhelpers;

alias X = int;

static if (defined!"DEF")
{
alias Y = int;
}
static if (!defined!"DEF" && defined!"DEF2")
{
/+ #define Y long +/
alias Y = long;
}
static if (!defined!"DEF" && !defined!"DEF2")
{
__gshared const(int) Y = 5;
}

static if (!defined!"DEF" && !defined!"DEF2")
{
__gshared auto f = X(Y);
}
static if (defined!"DEF" || defined!"DEF2")
{
X f(Y);
}

