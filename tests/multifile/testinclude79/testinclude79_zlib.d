
module testinclude79_zlib;

import config;
import cppconvhelpers;
static if (defined!"DEF" && defined!"Z_WANT64")
    import testinclude79_gzlib;

static if (defined!"DEF" && defined!"Z_WANT64")
{
/+ #  define gzopen gzopen64 +/
alias gzopen = gzopen64;
}

