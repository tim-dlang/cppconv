int f(int);
char f(char);

struct S
{
	S *f(int);
	void g()
	{
		#ifdef DEF
		int x = 42;
		#else
		char x = 42;
		#endif

		f(x);
	}
};
