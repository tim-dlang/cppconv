module testdefines22;

import config;
import cppconvhelpers;

/+ #ifndef DEF +/
static if (!defined!"DEF")
{
/+ #define DEF +/
void f();
}
/+ #elif defined(DEF) +/
static if (defined!"DEF")
{
void g();
}
/+ #else
void h();
#endif +/

