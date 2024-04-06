struct X
{
	struct S
	#ifdef DEF
	*s
	#endif
	;
	#ifndef DEF
	S *s;
	#endif
};

void f(
#ifdef DEF
S
#else
X::S
#endif
 *s)
{
	X x;
	x.s = s;
}
