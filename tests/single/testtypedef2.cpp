typedef struct
{
	int i;
}
#ifdef DEF
S
#else
T
#endif
;
#ifndef DEF
typedef T S;
#endif

void test(S){}

typedef S X;

void test2(X){}
