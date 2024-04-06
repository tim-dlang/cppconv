module test36;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
struct S1
{
int i1;
/+ #ifdef DEF +/
}
}
static if (!defined!"DEF")
{
struct S1{int i1;/+ struct S2
{
#endif +/
int i2;
}
}
static if (defined!"DEF")
{
struct S2{int i2;}
}

