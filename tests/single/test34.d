// defined has special meaning inside #if-expressions
// make sure those don't conflict with normal code.
module test34;

import config;
import cppconvhelpers;

int defined(int i)
{
	return i;
}
__gshared int i1 = defined(3);
/+ #define X defined(4) +/
enum X = q{defined(4)};
__gshared int i2 = mixin(X);
/+ #define f(x) defined(x) +/
extern(D) alias f = function string(string x)
{
    return mixin(interpolateMixin(q{defined($(x))}));
};
__gshared int i3 = mixin(f(q{5}));
/+ #define Y f(6) +/
enum Y = q{mixin(f(q{6}))};
__gshared int i4 = mixin(Y);
/+ #define g() X +/
extern(D) alias g = function string()
{
    return mixin(interpolateMixin(q{mixin(X)}));
};
__gshared int i5 = mixin(g());

