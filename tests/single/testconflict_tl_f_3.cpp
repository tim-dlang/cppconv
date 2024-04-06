#ifdef DEF
template<class T>
class C
{
public:
	enum {
		isLarge = (sizeof(T)>sizeof(void*)),
		isStatic = true
	};
};
typedef int X;
#else
int C, X, isLarge, isStatic;
#endif

template<class T>
void f()
{
	if(C<X>::isLarge || C<X>::isStatic)
	{}
}
