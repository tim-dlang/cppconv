template<class T>
bool f()
{
    return true;
}

struct S
{
    template<class T>
    bool f()
    {
        return true;
    }
};

void printf(const char *fmt, ...);

#define CHECK(statement) \
do { \
    if (!static_cast<bool>(statement)) \
        printf("Failed: %s\n", #statement); \
} while (false)

int main()
{
    CHECK(true);
    CHECK(f<S>());
    S x;
    CHECK(x.f<S>());
    return 0;
}
