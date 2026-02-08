namespace n
{
    struct S
    {
    };
    void g();
}

void f()
{
    using n::S;
    S *x;

    using n::g;
    g();
}
