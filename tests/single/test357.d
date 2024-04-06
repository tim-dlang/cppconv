// from zlib
module test357;

import config;
import cppconvhelpers;

/+ #define send_bits(value, length) \
{\
    int val = (int)value;\
} +/

/+ #define DYN_TREES    2 +/
enum DYN_TREES =    2;

void f(int last)
{
    /+ send_bits((DYN_TREES<<1)+last, 3) +/{int val=cast(int)(DYN_TREES<<1)+last;}
}

