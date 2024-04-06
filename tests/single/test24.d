module test24;

import config;
import cppconvhelpers;

/+ #ifdef D +/
static if (!defined!"D")
{
void a();
}
/+ #else
void b();
#endif

#ifndef D
void c();
#else +/
static if (!defined!"D")
{
void d();
}
/+ #endif +/

