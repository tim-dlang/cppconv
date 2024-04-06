module testconflict_vf_ccf_1;

import config;
import cppconvhelpers;

alias x = int;

struct S
{
	/+ static +/ struct Inner
	{
		void f()
		{
			void* g(.x);
		}/+ ; +/
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

