module test382;

import config;
import cppconvhelpers;

__gshared uint[3]  array = [1, 2, 3];

uint  f()
{
    uint  r = 0;
    foreach (uint  x; array)
    {
        r += x;
    }
    return r;
}

