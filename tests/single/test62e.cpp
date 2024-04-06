#ifdef DEF
typedef
#endif
enum
#ifndef DEF
E
#endif
{
	A,
	B,
	C
}
#ifdef DEF
E
#endif
;

void f(E);

void g()
{
	f(A);
}
