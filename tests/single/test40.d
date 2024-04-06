module test40;

import config;
import cppconvhelpers;

__gshared int a;
/+ #ifdef DEF
#ifdef DEF2
#else
#endif
#else
#ifdef DEF3
#else
#endif
#endif +/
__gshared int b;

