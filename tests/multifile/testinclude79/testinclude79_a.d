module testinclude79_a;

import config;
import cppconvhelpers;

/+ #undef ZLIB_INTERNAL +/

static if (defined!"DEF")
{

void f()
{
    static if (defined!"Z_WANT64")
        import testinclude79_zlib;
    static if (!defined!"Z_WANT64")
        import testinclude79_gzlib;

	mixin((defined!"Z_WANT64") ? q{
        	gzopen
    	} : q{
        gzopen
    	})();
}

}

