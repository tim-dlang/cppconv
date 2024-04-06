struct S
{
	#ifdef DEF
	int x;
	#define i x
	#else
	int y;
	#define i y
	#endif
};

int f(S *s)
{
	return s->i;
}
