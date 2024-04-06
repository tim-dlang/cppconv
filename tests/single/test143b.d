module test143b;

import config;
import cppconvhelpers;

alias intmax_t = long;
alias uintmax_t = ulong;

static if (defined!"_WIN32" && !defined!"__CYGWIN__")
{
	/+ #define INT64_MAX 9223372036854775807LL +/
enum INT64_MAX = 9223372036854775807L;
}
static if (!defined!"_WIN32" || defined!"__CYGWIN__")
{
	/+ #define INT64_MAX (9223372036854775807L) +/
enum INT64_MAX = (9223372036854775807L);
}

uintmax_t append_int(intmax_t d)
{
	uintmax_t ud;
	ud = cast(uintmax_t)( mixin(((defined!"_WIN32" && !defined!"__CYGWIN__")) ? q{
        	INT64_MAX
    	} : q{
        INT64_MAX
    	})) + 1;
	return ud;
}

