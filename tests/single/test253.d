
module test253;

import config;
import cppconvhelpers;

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

struct _7zip {

	uint64_t		 entry_bytes_remaining;
}

void	archive_entry_set_size(la_int64_t);

void f(_7zip* zip)
{
	archive_entry_set_size(zip.entry_bytes_remaining);
}

