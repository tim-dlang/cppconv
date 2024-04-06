template<class T>
struct QTypeInfo
{
	enum
	{
		isRelocatable = 1
	};
};

struct S
{
	enum E
	{
		X,
		Y
	};
};

void f()
{
	#define CHECK_TYPE(t, relocatable) do { \
		if(QTypeInfo<t>::isRelocatable == relocatable){} \
		} while(0);
	CHECK_TYPE(double, 1)
	CHECK_TYPE(S, 1)
	CHECK_TYPE(S*, 1)
	CHECK_TYPE(S::E, 1)
}
