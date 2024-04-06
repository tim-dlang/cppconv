template<class T>
struct List
{
	T *data();
};

struct S
{
};

void g(S *s);

void f(List<S> &l)
{
	g(l.data());
}
