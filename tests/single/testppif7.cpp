#ifdef DEF
#define X (2)
#elif defined(DEF2)
#define X (1)
#endif



#ifndef DEF3
#define Y (2)
#elif defined(DEF4)
#define Y (1)
#endif


#if (X == (Y))
int a;
#else
int b;
#endif
