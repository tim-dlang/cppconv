typedef int x;

struct S
{
	static struct Inner
	{
		auto f()
		{
			return (x)+1;
		}
	}
	d1,
	#ifdef DEF
	*x,
	#else
	*d2,
	#endif
	d3
	;
};
