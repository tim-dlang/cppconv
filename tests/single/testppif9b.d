module testppif9b;

import config;
import cppconvhelpers;

/+ #undef X
#ifdef DEF
#define X 0
#endif

#if !X +/
__gshared int a;
/+ #else
int b;
#endif +/

