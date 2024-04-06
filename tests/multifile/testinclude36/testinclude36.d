module testinclude36;

import config;
import cppconvhelpers;

/+ #define MACRO(x) ((x) + 1) +/
extern(D) alias MACRO = function string(string x)
{
    return mixin(interpolateMixin(q{(($(x)) + 1)}));
};
int f(int i)
{
	return mixin(MACRO(q{i}));
}

