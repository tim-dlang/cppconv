#if ((defined __WIN32__) || (defined _WIN32) || defined(__CYGWIN__)) && (!defined LIBARCHIVE_STATIC)
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
#endif

#if defined(_WIN32) && !defined(__CYGWIN__)
typedef long long int64_t;
typedef unsigned long long uint64_t;
#else
#if defined(__LP64__)
typedef long long int64_t;
typedef unsigned long long uint64_t;
#else
typedef long int64_t;
typedef unsigned long uint64_t;
#endif
#endif

# if defined(_WIN32) && !defined(__CYGWIN__) && !defined(__WATCOMC__)
typedef __int64 la_int64_t;
# else
typedef int64_t la_int64_t;
# endif

struct archive;

typedef la_int64_t	archive_skip_callback(struct archive *,
			    void *_client_data, la_int64_t request);

__LA_DECL int archive_read_set_skip_callback(struct archive *,
    archive_skip_callback *);

int
archive_read_set_skip_callback(struct archive *_a,
    archive_skip_callback *client_skipper)
{
	return 0;
}

int
archive_read_open2(struct archive *a,
    archive_skip_callback *client_skipper)
{
	archive_read_set_skip_callback(a, client_skipper);
	return 0;
}
