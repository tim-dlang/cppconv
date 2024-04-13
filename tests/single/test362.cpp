class Parent
{
public:
    virtual void f(int) {}
    void f(double) {}
};

class Child : public Parent
{
public:
    void f(int) {}
    void f(float) {}
};

class Child2 : public Child
{
public:
    void f(int) {}
};
