#ifdef DEF
const int T1 = 1;
#else
template<int a, int b>
struct T1
{
	T1(int x){}
};
#endif

template<class T>
void f2(T param)
{}
template<class T>
void f2(T param, T param2)
{}

void f()
{
	const int a = 2;
	const int b = 2;
	const int c = 2;
	f2(T1<a, b> (c));
}
