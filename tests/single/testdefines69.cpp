struct S
{
    S() = default;
    S(long long){}
};

#ifdef DEF
#define T int
#elif defined(DEF2)
#define T unsigned
#elif defined(DEF3)
#define T unsigned long long
#else
#define T S
#endif

T x;
const T x2 = 0;

void f(T y);
void f2(const T y);

template<typename T2>
struct S2
{
};

S2<T> z;
S2<const T> z2;
