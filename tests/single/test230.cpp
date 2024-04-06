class C1
{
public:
	C1(int x, int y) : x(x), y(y)
	{}

	int x, y;
};

class C2: public C1
{
public:
	C2(int x, int y) : C1(x, y)
	{}
};

class C3
{
public:
	C3(int x, int y) : c1(x, y)
	{}

	C1 c1;
};
