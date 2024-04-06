module testinclude74;

import config;
import cppconvhelpers;

/+ #define str(s) #s +/
extern(D) alias str = function string(string s)
{
    return mixin(interpolateMixin(q{$(stringifyMacroParameter(s))}));
};
/+ #define test str(test test) +/
enum test = mixin(str(q{test test}));

