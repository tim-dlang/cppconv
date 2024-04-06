module test35;

import config;
import cppconvhelpers;

/+ #ifdef DEF
#define X
#else
#define X __extension__
#endif +/

struct S
{
	/+ X +/ union U
	{
		/+ X +/ int i;
	}
}

