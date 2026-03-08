module test170;

import config;
import cppconvhelpers;

struct S
{
	const(char)* name;
	void function() f;
}

void f1();
void f2();

/+ #define M(x) {#x, x} +/
extern(D) alias M = function string(string x)
{
    return mixin(interpolateMixin(q{const(imported!q{test170}.S)($(stringifyMacroParameter(x)), $(x))}));
};

__gshared /+ const(S)[0]  +/ auto funcs = mixin(buildStaticArray!(q{const(S)}, q{ mixin(M(q{&f1})), mixin(M(q{&f2}))}));

