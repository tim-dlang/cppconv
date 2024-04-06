class A
{
public:
	void f();
};

class B: public A
{
public:
	using A::f;
};
