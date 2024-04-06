module test77;

import config;
import cppconvhelpers;

/+ #define __KHASH_TYPE(name, khkey_t, khval_t) \
	typedef struct kh_##name##_s { \
		unsigned int n_buckets, size, n_occupied, upper_bound; \
		unsigned int *flags; \
		khkey_t *keys; \
		khval_t *vals; \
	} kh_##name##_t;
#define khash_t(name) kh_##name##_t +/
struct kh_str_s{uint n_buckets;uint size;uint n_occupied;uint upper_bound;uint* flags;const(char)** keys;void** vals;}
alias kh_str_t = kh_str_s;

/+ __KHASH_TYPE(str, const char *, void *) +/
/+ khash_t(str) +/alias git_strmap = kh_str_t;

struct git_oid
{
}
struct kh_oid_s{uint n_buckets;uint size;uint n_occupied;uint upper_bound;uint* flags;const(git_oid)** keys;void** vals;}
alias kh_oid_t = kh_oid_s;
/+ __KHASH_TYPE(oid, const git_oid *, void *) +/
/+ khash_t(oid) +/alias git_oidmap = kh_oid_t;

