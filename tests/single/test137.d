module test137;

import config;
import cppconvhelpers;

/+ #ifdef ALWAYS_PREDEFINED_IN_TEST
#define __has_cpp_attribute(x) __has_cpp_attribute_ ## __cppconv_to_identifier(x)
#endif

#if __has_cpp_attribute(clang::fallthrough)
#define FALLTHROUGH [[clang::fallthrough]]
#elif __has_cpp_attribute(fallthrough)
#define FALLTHROUGH [[fallthrough]]
#elif defined(DEF)
#define	FALLTHROUGH	__attribute__((fallthrough))
#else
#define	FALLTHROUGH
#endif +/

void g();
void f(int level)
{
	switch (level)
	{
	case 4:
		g();
		static if ((defined!"DEF" || (configValue!"__has_cpp_attribute_clang_fallthrough" && defined!"__has_cpp_attribute_clang_fallthrough") || (configValue!"__has_cpp_attribute_fallthrough" && defined!"__has_cpp_attribute_fallthrough")))
		{
    		/+ FALLTHROUGH; +/
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
		static if ((defined!"DEF" || (configValue!"__has_cpp_attribute_clang_fallthrough" && defined!"__has_cpp_attribute_clang_fallthrough") || (configValue!"__has_cpp_attribute_fallthrough" && defined!"__has_cpp_attribute_fallthrough")))
		{
    		/+ FALLTHROUGH; +/
		}
		else
		{
		}
	goto case;
	case 5:
		g();
		/+ [[fallthrough]]; +/
	goto default;
	default:
		g();
	}
}

