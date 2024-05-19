template<typename T>
class C
{
};

void f()
{
    C<int> *c = new C<int>();

    int *p = new int();
}
