
struct A
{
    int i;
};
struct B
{
    int i;
};

struct S
{
    int i1;

    int i2;
    int i3;
#ifndef DEF
    int i4;
    int i5;
#endif

    A a;
    B b;
};

#ifdef DEF
template<typename T1, typename T2>
int f(int i)
{
    return i;
}

typedef int a;
typedef int b;

#else

const int f = 1;
const int a = 2;
const int b = 3;

#endif

void g()
{
    S data = {
        1,

        f<a, b>(2),
        f<a, b>(3),

        {4},
        {5}
    };
}
