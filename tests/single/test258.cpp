template<class T>
class Template
{
public:
	static void f();
	struct S
	{
	};
};

void g()
{
	Template<int>::f();
	Template<int>::S x;
}
