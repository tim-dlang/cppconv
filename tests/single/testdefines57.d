module testdefines57;

import config;
import cppconvhelpers;

/+ #define test_a(x) 2*x +/
template test_a(params...) if (params.length == 1)
{
    enum x = params[0];
    enum test_a = 2*x;
}
/+ #define test_b(x) 3*x +/
template test_b(params...) if (params.length == 1)
{
    enum x = params[0];
    enum test_b = 3*x;
}
/+ #define f(name, y) test_ ## name (y) +/

__gshared int i1 = test_a!(10)/+ f(a, 10) +/;
__gshared int i2 = test_b!(20)/+ f(b, 20) +/;

// tags: higher-order-macro

