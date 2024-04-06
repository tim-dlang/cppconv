module test297;

import config;
import cppconvhelpers;

/+ #  define Q_UINT64_C(c) ((unsigned long long)(c ## ULL)) +/

__gshared int a = (cast(int) (cast(ulong)(1UL)));
__gshared int b =    (cast(int) (cast(ulong)(2UL))) ;
__gshared int c = /*x*//*y*//*z*/(cast(int) (cast(ulong)(3UL)))/*w*/;
/+ #if 0
int d = Q_UINT64_C(4);
#endif +/

