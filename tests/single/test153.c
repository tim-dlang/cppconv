#ifdef __LP64__
typedef unsigned long uint64_t;
typedef long int64_t;
#else
typedef unsigned long long uint64_t;
typedef long long int64_t;
#endif

#if !defined(_WIN32) || defined(__CYGWIN__)
#ifdef __LP64__
#  define __UINT64_C(c)	c ## UL
#  define __INT64_C(c)	c ## L
#else
#  define __UINT64_C(c)	c ## ULL
#  define __INT64_C(c)	c ## LL
#endif
#endif

#if defined(_WIN32) && !defined(__CYGWIN__)
#define UINT64_MAX 0xffffffffffffffffULL /* 18446744073709551615ULL */
#define INT64_MAX 9223372036854775807LL
#else
# define UINT64_MAX		(__UINT64_C(18446744073709551615))
# define INT64_MAX		(__INT64_C(9223372036854775807))
#endif

int main()
{
	int64_t remaining=6;
	int64_t offset=0;
	if (remaining < 0 || offset < 0 || offset > INT64_MAX - remaining) {
		return 1;
	}
	return 0;
}

