enum E
{
	A,
	B
};

struct S
{

};

void *f(int);

void g()
{
	struct S *s = f(A);
};
