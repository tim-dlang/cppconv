enum E
{
	X,
	Y
};

E f()
{
	return E(1);
}

namespace N
{
enum E2
{
	X2,
	Y2
};
}

N::E2 f2()
{
	return N::E2(1);
}
