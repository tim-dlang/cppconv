module testinclude104b_enum;

import config;
import cppconvhelpers;

 mixin(q{enum E
    }
    ~ "{"
    ~ q{

        A,
        B,
    }
    ~ (defined!"DEF" ? q{
    /+ #ifdef DEF +/
        C,
    }:"")
    ~ q{
    /+ #endif +/
        D
    }
    ~ "}"
);
