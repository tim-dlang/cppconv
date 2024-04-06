class C1
{
public:
	C1(int i)
	{
	}
	C1() : C1(0)
	{
	}
	virtual ~C1() {}
};

class C2 : public C1
{
public:
	C2(int i) : C1(i)
	{
	}
	C2() : C2(0)
	{
	}
	virtual ~C2() {}
};

struct S1
{
public:
	S1(int i)
	{
	}
	S1() : S1(0)
	{
	}
};

struct S2 : public S1
{
public:
	S2(int i) : S1(i)
	{
	}
	S2() : S2(0)
	{
	}
};

