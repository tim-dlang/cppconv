#ifdef DEF
#define DEBUG_PARAMS1 , const char *function , unsigned line
#define DEBUG_PARAMS2 , __FUNCTION__ , __LINE__
#else
#define DEBUG_PARAMS1
#define DEBUG_PARAMS2
#endif

void f_(int i DEBUG_PARAMS1);
#define f(i) f_(i DEBUG_PARAMS2)

void g()
{
	f(5);
}
