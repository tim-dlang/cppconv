module testdefines71;

import config;
import cppconvhelpers;

__gshared const(int) g = 1;
/+ #define f(x) x +/
extern(D) alias f = function string(string x)
{
    return mixin(interpolateMixin(q{$(x)}));
};
/+ #define X (1*g) +/
enum X = q{(1*imported!q{testdefines71}.g)};
__gshared int i = mixin(f(X)) + 1;

/+ #define Y X +/
enum Y = imported!q{testdefines71}.X;
__gshared int i2 = mixin(Y);

/+ #define f2(y) f(y) +/
extern(D) alias f2 = function string(string y)
{
    return mixin(interpolateMixin(q{$(imported!q{testdefines71}.f(q{$(y)}))}));
};
__gshared int i3 = mixin(f2(X)) + 3;

