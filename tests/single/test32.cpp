#ifdef DEF
struct S
{
	int i;
	void f()
	{
		int x;
	}
	struct Inner
	{
		int x,y;
	} d;
	int different1;
};
#else
struct S
{
	int i;
	void f()
	{
		int x;
	}
	struct Inner
	{
		int x,y;
	} d;
	int different2;
};
#endif
