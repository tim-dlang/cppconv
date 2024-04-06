module testtypedef7;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X_TYPE int
#else
#define X_TYPE long
#endif +/
alias T = Identity!(mixin((defined!"DEF")?q{uint}:q{ulong})) /+ X_TYPE +/;

__gshared T data;

