module test6;

import config;
import cppconvhelpers;

int f1();
/+ #ifdef DEF
extern "C"
{
#endif +/
int f2();
int f3();
int f4();
/+ #ifdef DEF
}
#endif +/
int f5();

