template<typename T, class S>
class C
{
public:
	void f(T &t, S &s);
};

template<typename X, class Y>
void C<X,Y>::f(X &x, Y &y)
{
	x.i = y.i;
}
