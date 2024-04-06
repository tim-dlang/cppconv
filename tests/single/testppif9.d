module testppif9;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X 0
#endif +/

static if (!configValue!"X" || defined!"DEF" || !defined!"X")
{
__gshared int a;
}
static if (configValue!"X" && !defined!"DEF" && defined!"X")
{
__gshared int b;
}

