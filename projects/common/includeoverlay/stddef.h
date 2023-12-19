#ifndef _STDDEF_H
#define _STDDEF_H

#ifdef __cplusplus
#define NULL 0L
#else
#define NULL ((void*)0)
#endif

#ifdef __LP64__
#define _Addr long
#else
#define _Addr int
#endif

#ifndef _SIZE_T_DEFINED
typedef unsigned _Addr size_t;
#define __size_t
#define _SIZE_T_DEFINED
#endif

typedef _Addr ssize_t;
#define __ssize_t_defined
typedef _Addr ptrdiff_t;

#undef _Addr

#define offsetof(type, member) __builtin_offsetof(type, member)

#if defined(__cplusplus)
  typedef decltype(nullptr) nullptr_t;
#endif

#endif
