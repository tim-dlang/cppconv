module testppif4;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X (2)
#else
#define X (1)
#endif +/

static if (!defined!"DEF")
{
__gshared int a;
}
static if (defined!"DEF")
{
__gshared int b;
}

