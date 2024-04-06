module test37c;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF
#else +/
static if (!defined!"DEF")
{
__gshared int x;
}
/+ #endif +/
__gshared int b;

