template<class T>
void wrapper(T callback)
{
    int i = 1;
    callback(i);
}

template<class T>
void wrapper2(T callback)
{
    callback();
}

int f()
{
    int r = 0;
    wrapper([&r] (int i) {
        r += i;
    });
    wrapper([&r] (const int &i) {
        r += i;
    });
    wrapper2([&r] {
        r += 1;
    });
    wrapper([&r] (const int &i) -> bool {
        r += i;
        return true;
    });
    return r;
}
