module test384;

import config;
import cppconvhelpers;

void wrapper(T)(T callback)
{
    int i = 1;
    callback(i);
}

void wrapper2(T)(T callback)
{
    callback();
}

int f()
{
    int r = 0;
    wrapper(/+ [&r] +/ (int i) {
        r += i;
    });
    wrapper(/+ [&r] +/ (ref const(int) i) {
        r += i;
    });
    wrapper2(/+ [&r] +/() {
        r += 1;
    });
    wrapper(/+ [&r] +/ (ref const(int) i) /+ -> bool +/ {
        r += i;
        return true;
    });
    return r;
}

