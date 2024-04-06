module testdefines47;

import config;
import cppconvhelpers;

/+ #define g(x) x +/
template g(params...) if (params.length == 1)
{
    enum x = params[0];
    enum g = x;
}
/+ #define h(x) x +/
template h(params...) if (params.length == 1)
{
    enum x = params[0];
    enum h = x;
}
/+ #define f1(x) x +/
template f1(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f1 = x;
}
/+ #define f2(x) g(x) +/
template f2(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f2 = g!(x);
}
/+ #define f3(x) h(g(x)) +/
template f3(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f3 = h!(g!(x));
}
__gshared int test1 = f1!(g!(1));
__gshared int test2 = f2!(2);
__gshared int test3 = f2!(h!(3));
__gshared int test4 = f3!(4);
__gshared int test5 = f3!(g!(5));

