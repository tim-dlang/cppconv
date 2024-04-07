module test184;

import config;
import cppconvhelpers;

/+ #define __CONCAT(x,y)	x ## y
#define __THROW

#  define __DECL_SIMD_cos __DECL_SIMD_x86_64
#ifdef DEF
#  define __DECL_SIMD_x86_64 _Pragma ("omp declare simd notinbranch")
#else
#  define __DECL_SIMD_x86_64 __attribute__ ((__simd__ ("notinbranch")))
#endif

#define __SIMD_DECL(function) __CONCAT (__DECL_SIMD_, function)

#define _Mdouble_		double
#define __MATH_PRECNAME(name,r)	__CONCAT(name,r)

#define __MATHCALL_VEC(function, suffix, args) 	\
  __SIMD_DECL (__MATH_PRECNAME (function, suffix)) \
  __MATHCALL (function, suffix, args)

#define __MATHCALL(function,suffix, args)	\
  __MATHDECL (_Mdouble_,function,suffix, args)
#define __MATHDECL(type, function,suffix, args) \
  __MATHDECL_1(type, function,suffix, args); \
  __MATHDECL_1(type, __CONCAT(__,function),suffix, args)
#define __MATHDECL_1_IMPL(type, function, suffix, args) \
  extern type __MATH_PRECNAME(function,suffix) args __THROW
#define __MATHDECL_1(type, function, suffix, args) \
  __MATHDECL_1_IMPL(type, function, suffix, args) +/
static if (defined!"DEF")
{
double cos(double __x);
double __cos(double __x);
}
static if (!defined!"DEF")
{
double __cos(double __x);
double cos(double __x);
}

/+ __MATHCALL_VEC (cos,, (_Mdouble_ __x)); +/

