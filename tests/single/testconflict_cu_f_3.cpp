#ifdef DEF
int a;
#else
typedef int a;
#endif
int f()
{
	int b;
	return 2*(a)-b;
}
