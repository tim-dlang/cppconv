class Base
{
public:
    virtual ~Base()
    {}

    void f(int i)
    {}
};

class Child : public Base
{
public:
    using Base::f;
    void f(const char *s)
    {}
};

int main()
{
    Child *c = new Child();
    c->f(1);
    c->f("");
    return 0;
}
