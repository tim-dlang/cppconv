#define __KHASH_TYPE(name, khkey_t, khval_t) \
	typedef struct kh_##name##_s { \
		unsigned int n_buckets, size, n_occupied, upper_bound; \
		unsigned int *flags; \
		khkey_t *keys; \
		khval_t *vals; \
	} kh_##name##_t;
#define khash_t(name) kh_##name##_t

__KHASH_TYPE(str, const char *, void *)
typedef khash_t(str) git_strmap;

struct git_oid
{
};
__KHASH_TYPE(oid, const git_oid *, void *)
typedef khash_t(oid) git_oidmap;
