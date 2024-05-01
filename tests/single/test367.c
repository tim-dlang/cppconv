#ifdef ALWAYS_PREDEFINED_IN_TEST
#unknown X
#alias X1 X == 1
#alias X2 X == 2

#ifdef Y1
#imply defined(X1)
#endif

#ifdef Y2
#imply defined(X2)
#endif
#endif

#if defined(Y1) && defined(Y2)
void impossible();
#else
void f();
#endif
