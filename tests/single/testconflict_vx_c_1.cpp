typedef int T;
typedef int X;

struct S
{
	#ifdef DEF
	S
	#else
	T
	#endif
	(X);
};
