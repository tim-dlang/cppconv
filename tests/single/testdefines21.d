module testdefines21;

import config;
import cppconvhelpers;

/+ #define f(x) (x + 3) +/
template f(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f = (x + 3);
}
/+ #define g(x) (x / 5) +/
template g(params...) if (params.length == 1)
{
    enum x = params[0];
    enum g = (x / 5);
}
/+ #define X 42 +/
enum X = 42;
__gshared int test = f!(X * 2 - g!(60));

