#ifdef DEF
#define X (2)
#else
#define X (1)
#endif



#ifndef DEF2
#define Y 0
#else
#define Y 1
#endif

#define Z (Y + X)

#if (((Z) + 1) == 2)
int a;
#else
int b;
#endif
