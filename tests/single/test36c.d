module test36c;

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
/+ #ifndef DEF +/
}
}
static if (defined!"DEF")
{
struct S2{int i2;/+ struct S3
{
#endif +/
int i3;
}
}
static if (!defined!"DEF")
{
struct S3{int i3;}
}

