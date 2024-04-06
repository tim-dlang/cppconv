module test39d;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF
#elif defined(DEF2)
#elif defined(DEF3) +/
static if (!defined!"DEF" && !defined!"DEF2" && defined!"DEF3")
{
__gshared int x;
}
/+ #else
#endif +/
__gshared int b;

