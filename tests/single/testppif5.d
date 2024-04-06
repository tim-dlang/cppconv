module testppif5;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X (2)
#else
#define X (1)
#endif



#ifndef DEF2
#define Y 0
#else
#define Y 1
#endif

#define Z (Y + X) +/

static if (!defined!"DEF" && !defined!"DEF2")
{
__gshared int a;
}
static if (defined!"DEF" || defined!"DEF2")
{
__gshared int b;
}

