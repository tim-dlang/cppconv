struct
#ifdef DEF
S1
#else
S2
#endif
{
	int i;
};

typedef
#ifdef DEF
S1
#else
S2
#endif
T;

void test(T){}
