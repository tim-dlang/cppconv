module test17;

import config;
import cppconvhelpers;

/+ #ifdef DEF1
#elif defined(DEF2)
#elif defined(DEF3)
#else +/
static if (!defined!"DEF1" && !defined!"DEF2" && !defined!"DEF3")
{
__gshared int x;
}
/+ #endif +/

