typedef int x;

struct S
{
	static struct Inner
	{
		void f()
		{
			void* g(x);
		};
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
