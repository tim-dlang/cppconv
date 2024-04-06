module test139;

import config;
import cppconvhelpers;

/+ #undef X +/

__gshared int x =
/+ #if X
1
#else +/
2
/+ #endif +/
;

