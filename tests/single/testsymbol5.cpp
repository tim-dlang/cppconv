namespace n
{
	struct S
	{
	};
}

namespace n
{
	void f(S *s);
}

void g()
{
	n::S s;
	n::f(&s);
}
