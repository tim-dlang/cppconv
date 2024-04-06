class C1
{
public:
	enum E
	{
		E1,
		E2,
		E3
	};
	C1() : i(-1), p(nullptr), e(E3) {}
private:
	int i;
	void *p;
	E e;
};

class C2
{
public:
	enum E
	{
		E1,
		E2,
		E3
	};
	C2();
private:
	int i;
	void *p;
	E e;
};

C2::C2() : i(-2), p(nullptr), e(E2)
{
}
