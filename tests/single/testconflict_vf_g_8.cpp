typedef int X;

#ifdef DEF
typedef int Y;
#elif defined(DEF2)
#define Y long
#else
const int Y = 5;
#endif

X f(Y);
