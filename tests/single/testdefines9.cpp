#ifdef DEF
#define X 1
#elif defined(DEF2)
#define X 2
#else
#define X 3
#endif

#ifdef DEF
int test1 = X;
#else
int test2 = X;
#endif
