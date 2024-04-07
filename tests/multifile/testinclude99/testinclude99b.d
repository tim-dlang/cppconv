module testinclude99b;

import config;
import cppconvhelpers;

int f();
/+ #define X f() +/
enum X = q{imported!q{testinclude99b}.f()};

