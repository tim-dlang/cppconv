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
void f2(int i1, int i2, T param, int i4, int i5)
{}
template<class T>
void f2(int i1, int i2, T param, T param2, int i4, int i5)
{}

void f()
{
	const int a = 2;
	const int b = 2;
	const int c = 2;
	f2(1, 2, T1<a, b> (c), 4, 5);
}
