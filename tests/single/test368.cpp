
template<typename T>
int g(int i)
{
    return i;
}

template<typename T, typename T2>
int h(int i)
{
    return i;
}

template<typename T>
class C
{
};

template<typename T, typename T2>
class C2
{
    int f(int i)
    {
        return i;
    }
};

template<typename T>
int f()
{
    int arr[] = {
        1,
        g<C<T> >(2),
        3,
        g<T>(4),
        g<T>(5),
        C2<T, T>::f(6),
        9
    };
    return arr[1];
}
