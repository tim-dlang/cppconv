module testppif9d;

import config;
import cppconvhelpers;

/+ #undef X
#ifdef DEF
#define X 1
#endif +/

static if (!defined!"DEF")
{
__gshared int a;
}
static if (defined!"DEF")
{
__gshared int b;
}

