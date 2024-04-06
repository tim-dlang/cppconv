module testdefines55;

import config;
import cppconvhelpers;

/+ #define SIZE(t) (sizeof(t)) +/
template SIZE(params...) if (params.length == 1)
{
    alias t = params[0];
    enum SIZE = (t.sizeof);
}

__gshared ulong  s = SIZE!(long);

