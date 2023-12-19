#ifndef	_ASSERT_H
#define	_ASSERT_H	1

#undef assert

#define	assert(expr) __cppconv_assert((expr))

#if __STDC_VERSION__ >= 201112L && !defined(__cplusplus)
#define static_assert _Static_assert
#endif

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((__noreturn__)) void __assert_fail (const char *, const char *, int, const char *);

#ifdef __cplusplus
}
#endif

#endif
