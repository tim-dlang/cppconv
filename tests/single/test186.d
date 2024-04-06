
module test186;

import config;
import cppconvhelpers;

/+ #ifdef _WIN32
#   ifdef BZ_EXPORT
#   define BZ_API(func) func
#   define BZ_EXTERN extern
#   else
   /* import windows dll dynamically */
#   define BZ_API(func) (* func)
#   define BZ_EXTERN
#   endif
#else
#   define BZ_API(func) func
#   define BZ_EXTERN extern
#endif +/

static if (!defined!"BZ_EXPORT" && defined!"_WIN32")
{
int BZ2_bzCompressInit()
{
	return 0;
}
}
static if (defined!"BZ_EXPORT" || !defined!"_WIN32")
{
int BZ2_bzCompressInit(int workFactor){return 0;}
}

int BZ2_bzCompressInit2()
{
	return 0;
}

