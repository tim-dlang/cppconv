module testinclude106;

import config;
import cppconvhelpers;

static if (!defined!"DEF" && !defined!"DEF2" && !defined!"DEF3")
{
extern __gshared ubyte[16]  data;
}
/+ #define DATA1 data[1] +/
enum DATA1 = q{
    mixin(defined!"DEF" ? q{imported!q{testinclude106b}.data} : (!defined!"DEF" && defined!"DEF2") ? q{imported!q{testinclude106c}.data} : (!defined!"DEF" && !defined!"DEF2" && !defined!"DEF3") ? q{imported!q{testinclude106}.data} : q{imported!q{testinclude106d}.data})[1]};

