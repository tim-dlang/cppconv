module testppif1;

import config;
import cppconvhelpers;

/+ #define X(i) (i>0)

#if X(4) +/
void f();
/+ #define Y 1 +/
/+ #else
#define Y 2
#endif

#if X(0)
void g();
#define Z 1
#else
#define Z 2
#endif +/

