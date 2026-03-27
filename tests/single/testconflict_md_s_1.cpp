#ifdef DEF
class a
{
};
a *c;
#else
struct S
{
    S &operator *(S)
    {
        return *this;
    }
    explicit operator bool() const
    {
        return true;
    }
};
S a, b, c;
#endif
void f()
{
    if (a *b = c)
    {}
}
