struct S
{
};

void f(const S &s);

S &g()
{
    static S s;
    f(s);
    return s;
}

void h()
{
    S s;
    s = g();
}
