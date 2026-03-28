#ifdef ALWAYS_PREDEFINED_IN_TEST
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
#endif

void g();
void f(int level)
{
	switch (level)
	{
	case 4:
		g();
		FALLTHROUGH;
	case 3:
		g();
		__attribute__((fallthrough));
	case 2:
		g();
		FALLTHROUGH;
	case 5:
		g();
		[[fallthrough]];
	default:
		g();
	}
}
