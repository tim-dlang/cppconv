module test36b;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
struct S1
{
int i1;
/+ #ifdef DEF +/
}
struct S2
{
/+ #endif +/
int i2;
/+ #ifdef DEF +/
}
}
static if (!defined!"DEF")
{
struct S1{int i1;int i2;int i3;}
}
static if (defined!"DEF")
{
struct S3
{
/+ #endif +/
int i3;
}
}

