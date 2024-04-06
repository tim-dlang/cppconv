#define __CONCAT(x,y)	x ## y

#  define __DECL_SIMD_cos __attribute__ ((__simd__ ("notinbranch")))

#define _Mdouble_		double

#define __MATHDECL_1_IMPL(function, args) \
  extern double function args

__DECL_SIMD_cos
__MATHDECL_1_IMPL (cos, (_Mdouble_ __x));
