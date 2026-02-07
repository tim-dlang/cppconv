
struct S
{
    S(const char *);
};

struct C
{
    static void f(const S&);
};

void g()
{
    C::f("xyz");
    C::f(true ? "a" : "b");
}
