
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

struct _7zip {

	uint64_t		 entry_bytes_remaining;
};

void	archive_entry_set_size(la_int64_t);

void f(struct _7zip *zip)
{
	archive_entry_set_size(zip->entry_bytes_remaining);
}
