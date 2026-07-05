module test392;

import config;
import cppconvhelpers;

/+ #define IDENTITY(x) x +/
template IDENTITY(params...) if (params.length == 1)
{
    alias x = params[0];
    alias IDENTITY = x;
}

struct S
{
}

__gshared int s1 = cast(int) (IDENTITY!(int).sizeof);
__gshared int s2 = cast(int) (IDENTITY!(S).sizeof);

