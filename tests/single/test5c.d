//int f0();
module test5c;

import config;
import cppconvhelpers;

/+ #ifdef DEF +/
static if (defined!"DEF" && defined!"DEF1")
{
int f1();
}
static if (defined!"DEF" && defined!"DEF2")
{
int f2();
}
static if (defined!"DEF" && defined!"DEF3")
{
int f3();
}
static if (defined!"DEF" && defined!"DEF4")
{
int f4();
}
/+ #endif +/

