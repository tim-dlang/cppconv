module test21;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X
#else
#define X typedef
#endif +/

static if (defined!"DEF")
{
/+ X +/ __gshared int i1;
}
static if (!defined!"DEF")
{
alias i1 = int;
}
static if (defined!"DEF")
{
__gshared uint /+ X +/  i2;
}
static if (!defined!"DEF")
{
alias i2 = uint;
}
static if (defined!"DEF")
{
__gshared uint* /+ X +/  i3;
}
static if (!defined!"DEF")
{
alias i3 = uint*;
}

