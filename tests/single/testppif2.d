module testppif2;

import config;
import cppconvhelpers;

/+ #ifndef DEF
#define X 1
#endif +/
static if (!defined!"DEF" || defined!"X")
{
__gshared int a;
}
static if (defined!"DEF" && !defined!"X")
{
__gshared int b;
}

