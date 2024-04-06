module test116;

import config;
import cppconvhelpers;

 mixin(q{enum E1
    }
    ~ "{"
    ~ (defined!"DEF" ? q{

    /+ #ifdef DEF +/
    E1_A,
    }:"")
    ~ q{
    /+ #endif +/
    E1_B
    }
    ~ "}"
);
 mixin(q{enum E2
    }
    ~ "{"
    ~ q{

    E2_A
    }
    ~ (defined!"DEF" ? q{
    /+ #ifdef DEF +/
    ,E2_B
    /+ #endif +/
    }:"")
    ~ "}"
);
 mixin(q{enum E3
    }
    ~ "{"
    ~ q{

    E3_A,
    }
    ~ (defined!"DEF" ? q{
    /+ #ifdef DEF +/
    E3_B,
    }:"")
    ~ q{
    /+ #endif +/
    E3_C
    }
    ~ "}"
);

