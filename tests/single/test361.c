#ifdef ALWAYS_PREDEFINED_IN_TEST
#unknown X1
#unknown X2
#unknown X3
#unknown X4
#unknown X5
#endif

#if X1 == 1
void f1();
#elif X1 == 2
void f1();
#endif

#if X2 == 1
void f2();
#elif X2 == 2
void f2();
#endif

#if X3 == 1
void f3();
#elif X3 == 2
void f3();
#endif

#if X4 == 1
void f4();
#elif X4 == 2
void f4();
#endif

#if X5 == 1
void f5();
#elif X5 == 2
void f5();
#endif
