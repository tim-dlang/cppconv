module testinclude110;

import config;
import cppconvhelpers;

// Header comment for func1
/+ void func1(); +/

// Source comment for func1
void func1()
{
}

// Header comment for C
extern(C++, class) struct C
{
public:
    // Header comment for constructor
    // Source comment for constructor
    @disable this();
    /+this()
    {
    }+/

    // Header comment for destructor
    // Source comment for destructor
    ~this()
    {
    }

    // Header comment for inlinefunc
    int inlinefunc() {return 1;}

    // Header comment for memberfunc
    // Source comment for memberfunc
    int memberfunc()
    {
        return 2;
    }
}

// Header comment for func2
/+ void func2();
#undef TESTINCLUDE10_H +/
// Source comment for func2
void func2()
{
}

