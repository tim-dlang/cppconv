
struct S
{
    template<class T>
    bool f()
    {
        return true;
    }
    template<class T>
    S *f2()
    {
        return this;
    }
};

#ifdef DEF
#define NAME f
#else
#define NAME f2
#endif

#ifdef DEF
#define NAME2 p
#else
#define NAME2 arr
#endif

int main()
{
    S x;
    S arr[2];
    S *p = &x;
    x.f<S>();
    p->f<S>();
    arr->f<S>();
    x.f2<S>()->f<S>();
    x.NAME<S>();
    NAME2->f<S>();
    return 0;
}
