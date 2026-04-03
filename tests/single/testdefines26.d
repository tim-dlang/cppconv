module testdefines26;

import config;
import cppconvhelpers;

/+ #define __STRING(x)	#x +/
extern(D) alias __STRING = function string(string x)
{
    return	mixin(interpolateMixin(q{$(stringifyMacroParameter(x))}));
};
/+ #define __STRING2(x)	__STRING(x)
#define __STRING3(x)	__STRING(x x) +/
__gshared const(char)* s1 = mixin(__STRING(q{test}));
__gshared const(char)* s2 = mixin(__STRING(q{test2}))/+ __STRING2(test2) +/;
__gshared const(char)* s3 = mixin(__STRING(q{test3 test3}))/+ __STRING3(test3) +/;
/+ #define TEST2 test4 +/
__gshared const(char)* s4 = mixin(__STRING(q{TEST4}));
__gshared const(char)* s4b = mixin(__STRING(q{TEST4 x}));

__gshared const(char)* line1 = mixin(__STRING(q{__LINE__}));
__gshared const(char)* line2 = mixin(__STRING(q{__LINE__}))/+ __STRING2(__LINE__) +/;
__gshared const(char)* line3 = mixin(__STRING(q{__LINE__ __LINE__}))/+ __STRING3(__LINE__) +/;
/+ #define LOCATION __FILE__ ":" __STRING(__LINE__); +/
__gshared const(char)* location1 = /+ LOCATION +/__FILE__~ ":"~ mixin(__STRING(q{__LINE__}));


