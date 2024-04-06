module test22;

import config;
import cppconvhelpers;

__gshared int i1;
__gshared int* i2;
__gshared int[4] i3;
__gshared Identity!(mixin((defined!"DEF")?q{int function(int)
/+ #ifdef DEF +/
/+ (*i4)(int x)
#else
i4
#endif +/
}:q{int
/+ #ifdef DEF +/
/+ (*i4)(int x)
#else
i4
#endif +/
})) i4
;
__gshared int** i5;
static if (defined!"DEF2")
{
/+ #ifdef DEF2 +/
__gshared int*[4]* i6;
}
static if (!defined!"DEF2")
{

/+ #else +/
__gshared int i6
/+ #endif +/
;
}
__gshared int i7;

