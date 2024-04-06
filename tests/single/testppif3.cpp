#ifndef DEF
#define X 1
#endif
#define Y defined(X)
#if Y
int a;
#else
int b;
#endif
