template<typename T>
class C
{
public:
	C<T> createC1();

	struct S
	{
	};
	S createS1();
};

template<typename T>
C<T> C<T>::createC1()
{
	C<T> r;
	return r;
}

template<typename T>
typename C<T>::S C<T>::createS1()
{
	C<T>::S r;
	return r;
}
