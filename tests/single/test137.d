module test137;

import config;
import cppconvhelpers;

/+ #ifndef DEF
#define	__LA_FALLTHROUGH	__attribute__((fallthrough))
#else
#define	__LA_FALLTHROUGH
#endif +/

void g();
void f(int level)
{
	switch (level)
	{
	case 4:
		g();
		static if (!defined!"DEF")
		{
    		/+ __LA_FALLTHROUGH; +/
		}
		else
		{
		}
	goto case;
case 3:
		g();
		/+ __attribute__((fallthrough)); +/
	goto case;
case 2:
		g();
		static if (!defined!"DEF")
		{
    		/+ __LA_FALLTHROUGH; +/
		}
		else
		{
		}
	goto default;
default:
		g();
	}
}

