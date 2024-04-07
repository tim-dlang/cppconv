module testinclude98b;

import config;
import cppconvhelpers;

alias Int32 = int;

int f();
/+ #define X f() +/
enum X = q{imported!q{testinclude98b}.f()};

