module test39e;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF
#elif defined(DEF2)
#elif defined(DEF3)
#else +/
static if (!defined!"DEF" && !defined!"DEF2" && !defined!"DEF3")
{
__gshared int x;
}
/+ #endif +/
__gshared int b;

