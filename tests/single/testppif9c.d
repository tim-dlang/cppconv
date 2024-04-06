module testppif9c;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X 1
#endif +/

static if (!defined!"DEF" && (!configValue!"X" || !defined!"X"))
{
__gshared int a;
}
static if (defined!"DEF" || (configValue!"X" && defined!"X"))
{
__gshared int b;
}

