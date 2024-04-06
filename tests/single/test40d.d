module test40d;

import config;
import cppconvhelpers;

__gshared int a;
static if (defined!"DEF")
{
/+ #ifdef DEF2
#else
#endif +/
}
static if (!defined!"DEF")
{
/+ #ifdef DEF3 +/
static if (defined!"DEF3")
{
__gshared int x;
}
/+ #else
#endif +/
}
__gshared int b;

