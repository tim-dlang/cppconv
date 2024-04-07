module test153;

import config;
import cppconvhelpers;

static if (defined!"__LP64__")
{
alias uint64_t = ulong;
alias int64_t = long;
}
static if (!defined!"__LP64__")
{
alias uint64_t = ulong;
alias int64_t = long;
}

/+ #if !defined(_WIN32) || defined(__CYGWIN__)
#ifdef __LP64__
#  define __UINT64_C(c)	c ## UL
#  define __INT64_C(c)	c ## L
#else
#  define __UINT64_C(c)	c ## ULL
#  define __INT64_C(c)	c ## LL
#endif
#endif +/

static if (defined!"_WIN32" && !defined!"__CYGWIN__")
{
/+ #define UINT64_MAX 0xffffffffffffffffULL +/ /* 18446744073709551615ULL */
/+ #define INT64_MAX 9223372036854775807LL +/
enum INT64_MAX = 9223372036854775807L;
}
static if (!defined!"_WIN32" || defined!"__CYGWIN__")
{
/+ # define UINT64_MAX		(__UINT64_C(18446744073709551615)) +/
/+ # define INT64_MAX		(__INT64_C(9223372036854775807)) +/
enum INT64_MAX =		( mixin((defined!"__LP64__") ? q{
            		/+ __INT64_C(9223372036854775807) +/9223372036854775807L
        		} : q{
            9223372036854775807L
        		}));
}

int main()
{
	int64_t remaining=6;
	int64_t offset=0;
	if ( mixin(((defined!"_WIN32" && !defined!"__CYGWIN__")) ? q{
        	remaining < 0 || offset < 0 || offset > INT64_MAX - remaining
    	} : q{
        remaining<0||offset<0||offset> INT64_MAX-remaining
    	})) {
		return 1;
	}
	return 0;
}

