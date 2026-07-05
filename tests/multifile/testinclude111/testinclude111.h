#define M(x) x

const int i = M(
#ifdef IN_A
1
#else
2
#endif
);

#define STRINGIFY(x) #x

const char * const str = STRINGIFY(
#ifdef IN_A
A
#else
B
#endif
);
