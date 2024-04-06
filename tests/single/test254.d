module test254;

import config;
import cppconvhelpers;

/+ #if ((defined __WIN32__) || (defined _WIN32) || defined(__CYGWIN__)) && (!defined LIBARCHIVE_STATIC)
# ifdef __LIBARCHIVE_BUILD
#  ifdef __GNUC__
#   define __LA_DECL	__attribute__((dllexport)) extern
#  else
#   define __LA_DECL	__declspec(dllexport)
#  endif
# else
#  ifdef __GNUC__
#   define __LA_DECL
#  else
#   define __LA_DECL	__declspec(dllimport)
#  endif
# endif
#else
/* Static libraries or non-Windows needs no special declaration. */
# define __LA_DECL
#endif +/

static if (defined!"_WIN32" && !defined!"__CYGWIN__")
{
alias int64_t = long;
alias uint64_t = ulong;
}
static if (!defined!"_WIN32" || defined!"__CYGWIN__")
{
static if (defined!"__LP64__")
{
alias int64_t = long;
alias uint64_t = ulong;
}
static if (!defined!"__LP64__")
{
alias int64_t = long;
alias uint64_t = ulong;
}
}

static if (defined!"_WIN32" && !defined!"__CYGWIN__" && !defined!"__WATCOMC__")
{
alias la_int64_t = long;
}
static if (!defined!"_WIN32" || defined!"__CYGWIN__" || defined!"__WATCOMC__")
{
alias la_int64_t = int64_t;
}

struct archive;

alias archive_skip_callback = la_int64_t function(archive* ,
			    void* _client_data, la_int64_t request);

/+ __LA_DECL int archive_read_set_skip_callback(struct archive *,
    archive_skip_callback *); +/

int
archive_read_set_skip_callback(archive* _a,
    archive_skip_callback client_skipper)
{
	return 0;
}

int
archive_read_open2(archive* a,
    archive_skip_callback client_skipper)
{
	archive_read_set_skip_callback(a, client_skipper);
	return 0;
}

