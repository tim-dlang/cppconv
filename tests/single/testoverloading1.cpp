void f(int);
char *f(const char *);

void g()
{
	#ifdef DEF
	int x = 42;
	#else
	const char *x = "test";
	#endif

	f(x);
}
