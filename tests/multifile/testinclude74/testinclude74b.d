module testinclude74b;

import config;
import cppconvhelpers;
import testinclude74;

__gshared const(char)* testb = test;
__gshared const(char)* testb2 = mixin(str(q{a b}));

