// from zlib

#define send_bits(value, length) \
{\
    int val = (int)value;\
}

#define DYN_TREES    2

void f(int last)
{
    send_bits((DYN_TREES<<1)+last, 3);
}
