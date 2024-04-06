module test13;

import config;
import cppconvhelpers;

int f1();
/+ #ifdef DEF
extern "C"
{
#endif +/

int f2();

/+ #ifdef DEF2
extern "C++"
{
#endif +/

int f3();
static if (defined!"DEF3")
{
int f4();
}
int f5();

/+ #ifdef DEF2
}
#endif +/

int f6();

/+ #ifdef DEF
}
#endif +/
int f7();

