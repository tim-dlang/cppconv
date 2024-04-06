module test37b;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF +/
static if (defined!"DEF")
{
__gshared int x;
}
/+ #else
#endif +/
__gshared int b;

