//int f0();
module test5b;

import config;
import cppconvhelpers;

static if (defined!"DEF1")
{
int f1();
int f1b();
}
static if (defined!"DEF2")
{
int f2();
int f2b();
}
static if (defined!"DEF3")
{
int f3();
int f3b();
}
static if (defined!"DEF4")
{
int f4();
int f4b();
}

