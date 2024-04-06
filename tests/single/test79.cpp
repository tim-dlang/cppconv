struct S;

#ifdef DEF2
struct S;
#endif
#ifdef DEF3
struct S;
#endif
#ifdef DEF4
struct S;
#endif

#ifdef DEF
struct S
{
	int i;
};
#else
struct S
{
	long i;
};
#endif

#ifdef DEF5
struct S;
#endif
#ifdef DEF6
struct S;
#endif
#ifdef DEF7
struct S;
#endif
