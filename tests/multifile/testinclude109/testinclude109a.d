module testinclude109a;

import config;
import cppconvhelpers;
import testinclude109b;

class Child : Base
{
public:
    ~this() {}
    extern(C++) override void f() {}
    extern(C++) override void g()
    {
    }
}

