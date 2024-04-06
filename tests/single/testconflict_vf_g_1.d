
module testconflict_vf_g_1;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
alias x = int;
}
static if (!defined!"DEF")
{
__gshared const(int) x=0;
}


static if (defined!"DEF")
{
int f(x);
}
static if (!defined!"DEF")
{
__gshared auto f = int(x);
}

