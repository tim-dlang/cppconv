module testinclude74a;

import config;
import cppconvhelpers;
import testinclude74;

__gshared const(char)* testa = test;
__gshared const(char)* testa2 = mixin(str(q{x/+ char +/y z}));

