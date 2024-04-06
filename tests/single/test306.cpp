void f();

class C
{
	void f();
	void g()
	{
		::f();
	}
};
