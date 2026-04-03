module test391;

import config;
import cppconvhelpers;

void func_impl(int i, const(char)* file, int line);
/+ #define func(i) func_impl(i, __FILE__, __LINE__) +/
extern(D) alias func = function string(string i)
{
    return mixin(interpolateMixin(q{imported!q{test391}.func_impl($(i), __FILE__, __LINE__)}));
};

void main()
{
    (mixin(func(q{1})));
}

