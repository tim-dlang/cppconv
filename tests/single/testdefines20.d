module testdefines20;

import config;
import cppconvhelpers;

int g(int);
/+ #define f1(x) (x + 3) +/
template f1(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f1 = (x + 3);
}
__gshared int test = f1!(f1!(f1!(42)));
/+ #define X f1(f1(f1(43))) +/
enum X = f1!(f1!(f1!(43)));
__gshared int test2 = X;
/+ #define Y() f1(f1(f1(44))) +/
template Y(params...) if (params.length == 0)
{
    enum Y = f1!(f1!(f1!(44)));
}
__gshared int test3 = Y!();

