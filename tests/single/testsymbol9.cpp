class A
{
public:
	class C;
};

class A::C
{
public:
	typedef int D;
};

class B
{
public:
	A::C f();
};

A::C::D d;
