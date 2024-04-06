module test40b;

import config;
import cppconvhelpers;

__gshared int a;
static if (defined!"DEF")
{
/+ #ifdef DEF2 +/
static if (defined!"DEF2")
{
__gshared int x;
}
/+ #else
#endif +/
}
static if (!defined!"DEF")
{
/+ #ifdef DEF3
#else
#endif +/
}
__gshared int b;

