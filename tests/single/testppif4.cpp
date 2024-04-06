#ifdef DEF
#define X (2)
#else
#define X (1)
#endif

#if (((X) + 1) == 2)
int a;
#else
int b;
#endif
