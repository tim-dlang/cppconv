#ifdef ALWAYS_PREDEFINED_IN_TEST
#ifdef DEF1
#imply !defined(DEF2)
#endif
#endif

#ifndef DEF2
const int X = 5;
#else
typedef int X;
#endif
