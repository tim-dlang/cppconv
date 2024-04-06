int f(int);
char f(char);

void g()
{
	#ifdef DEF
	int x = 42;
	#else
	char x = 42;
	#endif

	f(x);
}
