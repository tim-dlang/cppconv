#ifdef DEF
#define A 1
#endif
#ifdef DEF2
#define B 1
#endif

#if (A && B) >= 1
void f();
#endif
