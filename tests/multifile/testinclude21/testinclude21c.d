module testinclude21c;

import config;
import cppconvhelpers;
import testinclude21;

/+ #define ALWAYS_PREDEFINED_IN_TEST +/
__gshared int i = X;

