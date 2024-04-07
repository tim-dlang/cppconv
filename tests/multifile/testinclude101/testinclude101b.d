module testinclude101b;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
/+ #define Y int +/
alias Y = int;
}

