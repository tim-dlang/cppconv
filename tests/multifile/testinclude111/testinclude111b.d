module testinclude111b;

import config;
import cppconvhelpers;
import testinclude111;

/+ #undef IN_A +/
__gshared const(char)* a = mixin(STRINGIFY(q{B}));

void g()
{
    const(int) i_b = i;
    const(char)* str_b = cast(const(char)*) (str);
}

