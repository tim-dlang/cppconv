template<class T>
void f(T t)
{
}

typedef int X;

int main()
{
	f<X>(5);
	return 0;
}
