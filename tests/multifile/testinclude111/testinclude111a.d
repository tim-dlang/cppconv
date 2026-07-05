module testinclude111a;

import config;
import cppconvhelpers;
import testinclude111;

/+ #define IN_A +/
__gshared const(char)* a = mixin(STRINGIFY(q{A}));

void f()
{
    const(int) i_a = i;
    const(char)* str_a = cast(const(char)*) (str);
}

