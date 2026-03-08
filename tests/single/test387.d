module test387;

import config;
import cppconvhelpers;

bool f(T)()
{
    return true;
}

struct S
{
    /+ template<class T> +/
    bool f(T)()
    {
        return true;
    }
}

void printf(const(char)* fmt, ...);

/+ #define CHECK(statement) \
do { \
    if (!static_cast<bool>(statement)) \
        printf("Failed: %s\n", #statement); \
} while (false) +/
extern(D) alias CHECK = function string(string statement)
{
    return
    mixin(interpolateMixin(q{    do {
            if (!static_cast!(bool)($(statement)))
                imported!q{test387}.printf("Failed: %s\n", $(stringifyMacroParameter(statement)));
        } while (false);}));
};

int main()
{
    mixin(CHECK(q{true}));
    mixin(CHECK(q{f!(S)()}));
    S x;
    mixin(CHECK(q{x.f!(S)()}));
    return 0;
}

