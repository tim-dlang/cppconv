module test17b;

import config;
import cppconvhelpers;

/+ #ifdef DEF1 +/
static if (defined!"DEF2")
{
/+ #if defined(DEF3)
#else +/
static if (defined!"DEF1" && !defined!"DEF3")
{
__gshared int x;
}
/+ #endif +/
}
/+ #endif +/

