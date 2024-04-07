module testconflict_vf_f_1;

import config;
import cppconvhelpers;

alias I = int;
void f()
{
double x(.I)/+ ,
#ifndef DEF
I
#else
dummy
#endif
, y(I) +/;static if (!defined!"DEF")
{
double I__1;
}
static if (defined!"DEF")
{
double dummy;
}
static if (!defined!"DEF")
{
auto y = double(I__1);
}
static if (defined!"DEF")
{
double y(.I);
}
}

