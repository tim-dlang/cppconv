#ifdef DEF
#define A 1
#else
#define A 2
#endif

#define f(x) (x)

int x = f(A);
int y = 3*f(4+A+5);
