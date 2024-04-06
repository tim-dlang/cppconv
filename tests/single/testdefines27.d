module testdefines27;

import config;
import cppconvhelpers;

/+ #define x 2 +/
/+ #define f(x) x*42 +/
template f(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f = x*42;
}
__gshared int y = f!(3);

