module testconflict_cp_ccf_1;

import config;
import cppconvhelpers;

alias x = int;

struct S
{
	/+ static +/ struct Inner
	{
		auto f()
		{
			return cast(.x)+1;
		}
	}
extern static __gshared Inner	d1;
static if (defined!"DEF")
{
	/+ #ifdef DEF +/
	extern static __gshared Inner* x;
}
static if (!defined!"DEF")
{
	/+ #else +/
	extern static __gshared Inner* d2;
}
	/+ #endif +/
	extern static __gshared Inner d3
	;
}

