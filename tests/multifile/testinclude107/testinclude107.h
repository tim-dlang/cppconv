#ifdef DEF
#ifdef DEF2
typedef struct S
{

} S;
#else
typedef struct S2
{

} S2;
#define S S2
#endif
#else
#define S unsigned int
#endif
