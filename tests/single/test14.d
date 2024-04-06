module test14;

import config;
import cppconvhelpers;

int f1();

/+ #ifdef DEF
extern "C"
{
#endif +/

int f2();

/+ #ifdef DEF
}
#endif +/

int f3();

/+ #ifdef DEF3
extern "C"
{
#endif +/

int f4();

/+ #ifdef DEF3
}
#endif +/

int f5();

