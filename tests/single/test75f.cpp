struct X
{
	struct S {
		int i;
	} *s;
};

void f(X::S *s)
{
	X x;
	x.s = s;
}

