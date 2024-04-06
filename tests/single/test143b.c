typedef long long intmax_t;
typedef unsigned long long uintmax_t;

#if defined(_WIN32) &&  !defined(__CYGWIN__)
	#define INT64_MAX 9223372036854775807LL
#elif (!defined(_WIN32) || defined(__CYGWIN__))
	#define INT64_MAX (9223372036854775807L)
#endif

uintmax_t append_int(intmax_t d)
{
	uintmax_t ud;
	ud = (uintmax_t)(INT64_MAX) + 1;
	return ud;
}
