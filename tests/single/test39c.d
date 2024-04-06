module test39c;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF
#elif defined(DEF2) +/
static if (!defined!"DEF" && defined!"DEF2")
{
__gshared int x;
}
/+ #elif defined(DEF3)
#else
#endif +/
__gshared int b;

