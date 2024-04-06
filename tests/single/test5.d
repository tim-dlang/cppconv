//int f0();
module test5;

import config;
import cppconvhelpers;

static if (defined!"DEF1")
{
int f1();
}
static if (defined!"DEF2")
{
int f2();
}
static if (defined!"DEF3")
{
int f3();
}
static if (defined!"DEF4")
{
int f4();
}

