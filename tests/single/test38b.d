module test38b;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF +/
static if (defined!"DEF")
{
__gshared int x;
}
/+ #elif DEF2
#else
#endif +/
__gshared int b;

