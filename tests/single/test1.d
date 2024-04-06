module test1;

import config;
import cppconvhelpers;

__gshared int i0=0;
__gshared int i1=1;
static if (defined!"DEF")
{
__gshared int i2a=2;
}
static if (!defined!"DEF")
{
__gshared int i2b=2;
}
__gshared int i3=3;
__gshared int i4=4;

