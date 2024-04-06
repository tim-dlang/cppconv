module test18;

import config;
import cppconvhelpers;

/+ #ifdef DEF1 +/
static if (defined!"DEF1")
{
__gshared int x;
}
/+ #elif defined(DEF2) +/
static if (!defined!"DEF1" && defined!"DEF2")
{
__gshared int y;
}
/+ #else +/
static if (!defined!"DEF1" && !defined!"DEF2")
{

/+ #endif +/
void f();
}
static if (defined!"DEF1" || defined!"DEF2")
{
void f();
}

