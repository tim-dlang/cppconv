module test39b;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF +/
static if (defined!"DEF")
{
__gshared int x;
}
/+ #elif defined(DEF2)
#elif defined(DEF3)
#else
#endif +/
__gshared int b;

