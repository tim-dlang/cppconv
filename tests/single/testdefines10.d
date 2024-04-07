module testdefines10;

import config;
import cppconvhelpers;

/+ #define A 1 +/
/+ #define f(x,y,z) A +/
extern(D) alias f = function string(string x, string y, string z)
{
    return mixin(interpolateMixin(q{imported!q{testdefines10}.A}));
};
/+ #define A 2 +/
enum A = 2;
__gshared int x = mixin(f
(q{
a},q{
b},q{
c
}));

