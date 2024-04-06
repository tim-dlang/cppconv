#ifdef DEF1
#define X 1
int x1;
#elif defined(DEF2)
#define X 2
int x2;
#elif defined(DEF3)
#define X 3
int x3;
#else
#define X -1
int x4;
#endif

int test = X;
