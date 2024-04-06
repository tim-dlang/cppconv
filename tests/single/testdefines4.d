module testdefines4;

import config;
import cppconvhelpers;

/+ #define f() 1 +/
template f(params...) if (params.length == 0)
{
    enum f = 1;
}
__gshared int x1 = f!();

