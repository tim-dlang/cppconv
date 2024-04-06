struct S{};
struct X
{
	struct S{};
	struct S *s;
};

void f(
X::S
 *s)
{
	X x;
	x.s = s;
}
