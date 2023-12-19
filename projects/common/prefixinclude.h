
// https://gcc.gnu.org/onlinedocs/cpp/Standard-Predefined-Macros.html
// https://gcc.gnu.org/onlinedocs/cpp/Common-Predefined-Macros.html

#regex_undef "(?!HAVE).*_H"
#regex_undef "INCLUDE_.*"
#regex_undef "__.*_h"
#regex_undef "__.*_H__"
#regex_undef ".*_defined"
#regex_undef "__.*_TYPE__"
#regex_undef ".*_H_"
#regex_undef ".*_h__"
#regex_undef ".*_DEFINED__"
#regex_undef "_INC_.*"
#regex_undef ".*_DEFINED"
#regex_undef ".*_h"
#regex_undef ".*_INCLUDED"
#regex_undef "_.*_TCC"
#regex_undef "__WINE_PSHPACK.*"
#regex_undef "__need_.*"
#regex_undef "U_.*"
#regex_undef ".*_INCLUDE__"
#regex_undef "_GLIBCXX.*"
#regex_undef "__GLIBCXX.*"
#regex_undef "Q_CC_.*"
#regex_undef "Q_OS_.*"

#undef __WINE_INTERNAL_POPPACK

#unknown CPPCONV_OS
#alias CPPCONV_OS_LINUX CPPCONV_OS == 1
#alias _WIN32 CPPCONV_OS == 2
#alias CPPCONV_OS_MACOS CPPCONV_OS == 3
#alias CPPCONV_OS_IOS CPPCONV_OS == 4
#alias CPPCONV_OS_TVOS CPPCONV_OS == 5
#alias CPPCONV_OS_WATCHOS CPPCONV_OS == 6

#undef __APPLE__
#if defined(CPPCONV_OS_MACOS) || defined(CPPCONV_OS_IOS) || defined(CPPCONV_OS_TVOS) || defined(CPPCONV_OS_WATCHOS)
#define __APPLE__
#define TARGET_OS_MAC 1
#endif

#undef TARGET_OS_IPHONE
#undef TARGET_OS_WATCH
#undef TARGET_OS_TV
#if defined(CPPCONV_OS_IOS) || defined(CPPCONV_OS_TVOS) || defined(CPPCONV_OS_WATCHOS)
#define TARGET_OS_IPHONE 1
#endif
#if defined(CPPCONV_OS_TVOS)
#define TARGET_OS_TV 1
#endif
#if defined(CPPCONV_OS_WATCHOS)
#define TARGET_OS_WATCH 1
#endif

#ifndef _WIN32
#undef __CYGWIN__
#undef WIN64
#undef _WIN64
#undef __WIN64__
#undef WIN32
#undef _WIN32
#undef __WIN32__
#undef __NT__
#endif

#undef __linux__
#undef __linux
#ifdef CPPCONV_OS_LINUX
#define __linux__
#define __linux
#endif

#ifndef CPPCONV_OS_LINUX
#undef ANDROID
#undef __ANDROID__
#undef __WEBOS__
#endif

#undef SAG_COM
#undef _LIBOBJC
#undef _LIBOBJC_WEAK

#undef __ARMCC__
#undef __CC_ARM
#undef __BORLANDC__
#undef __DMC__
#undef __TURBOC__
#undef __SC__
#undef __INTEL_COMPILER
#undef __clang__

#include "prefixinclude-paths.h"

#undef __cplusplus
#undef _MSC_VER
#undef DOCURIUM
#undef __ASSEMBLER__

#undef _GCC_LIMITS_H_
#undef _LIMITS_H___

#define __GNUC__ 8
#define __GNUC_MINOR__ 3
#define __GNUC_PATCHLEVEL__ 0
#undef _LIBC
#define __GNUC_STDC_INLINE__ 1
#undef __GNUG__
#undef __has_builtin
#undef __LDBL_COMPAT
#undef __LDBL_REDIR_DECL
#define _LARGEFILE_SOURCE
#define _LARGEFILE64_SOURCE
#define __STDC_HOSTED__ 1
#define _DEFAULT_SOURCE

#define __CHAR_BIT__ 8
#define __SHRT_MAX__ 0x7fff
#define __SCHAR_MAX__ 0x7f

#ifdef __LP64__
#define _Addr long
#define __SIZE_MAX__ 0xfffffffffffffffful
#else
#define _Addr int
#define __SIZE_MAX__ 0xffffffffu
#endif

typedef unsigned _Addr size_t;
#define __size_t
#define _SIZE_T_DEFINED

//typedef _Addr ssize_t;

#undef _Addr

#define __INT_MAX__ 0x7fffffffu
#define __LONG_MAX__ 0x7fffffffffffffffu
#define __LONG_LONG_MAX__ 0x7fffffffffffffffu

#undef _FORTIFY_SOURCE

#define WIN32_LEAN_AND_MEAN
#undef INC_OLE2
#undef _WINDEF_
#undef _WINNT_
#define NOWINRES
#define NOGDI
#define _WINUSER_
#unknown STRICT
#undef _WINSOCK2API_
#undef INCL_WINSOCK_API_TYPEDEFS
#define __stdcall
#define __cdecl
#define UNICODE
#undef WINE_NO_UNICODE_MACROS
#undef __WINESRC__
#undef USE_WS_PREFIX
#undef _DWORDLONG_
#undef _ULONGLONG_
#undef DWORDLONG
#undef __WIDL__
#undef __midl
#undef NOMINMAX
#undef DECLSPEC_ALIGN
#define WINE_UNICODE_NATIVE

#define INCLUDE_features_h__

#define __signed__ signed

#undef __NO_LONG_DOUBLE_MATH

#undef __GNUC_VA_LIST
#undef _VA_LIST
#undef __need___va_list

#undef VOID
//#define _TIME_T_DEFINED
#define _INTPTR_T_DEFINED

#define NULL __cppconv_nullptr
#lockdefine NULL

#undef _STRUCT_TIMESPEC
#undef _IO_USE_OLD_IO_FILE

#undef __OPTIMIZE__

#undef FD_CLR
#undef FD_ZERO
#undef RLIM_INFINITY
#undef _WINSOCKAPI_
#undef SIZE_MAX
#undef S_ISDIR
#undef NO_ADDRINFO
#undef __va_list__
#undef __VA_LIST
#undef __ms_va_list
#undef _VA_LIST_
#undef RC_INVOKED
#undef __WS2TCPIP__
#undef NONAMELESSUNION
#undef NONAMELESSSTRUCT
#undef INCL_WINSOCK_API_PROTOTYPES
#undef WS_DEFINE_SELECT
#undef CURL_DISABLE_TYPECHECK
#undef curl_socket_typedef
#undef NO_ASN1_TYPEDEFS

#define DECLSPEC_HIDDEN __attribute__((visibility ("hidden")))
#lockdefine DECLSPEC_HIDDEN
#define DECLSPEC_ALIGN(x) __attribute__((aligned(x)))
#lockdefine DECLSPEC_ALIGN
#define DECLSPEC_NORETURN __attribute__((noreturn))
#lockdefine DECLSPEC_NORETURN
#define DECLSPEC_NOTHROW __attribute__((nothrow))
#lockdefine DECLSPEC_NOTHROW
#define DECLSPEC_IMPORT __attribute__((dllimport))
#lockdefine DECLSPEC_IMPORT

#if defined(_WIN32) && !defined(__CYGWIN__)
#define __builtin_ms_va_list __builtin_va_list
#define __builtin_ms_va_start(list,arg) __builtin_va_start(list,arg)
#define __builtin_ms_va_end(list) __builtin_va_end(list)
#define __builtin_ms_va_copy(dest,src) __builtin_va_copy(dest,src)
#  define __ms_va_list __builtin_ms_va_list
#  define __ms_va_start(list,arg) __builtin_ms_va_start(list,arg)
#  define __ms_va_end(list) __builtin_ms_va_end(list)
#  define __ms_va_copy(dest,src) __builtin_ms_va_copy(dest,src)
#endif

#undef _SYSTEMTIME_
#undef _APISETTIMEZONE_

#undef __BEGIN_DECLS
#undef __END_DECLS
#undef FORCEINLINE
#undef _EXTERN_INLINE
#undef _Restrict_
#undef _Restrict_arr_

#define __FBSDID(a)

#undef __WIN32
#undef __WIN32__
#if defined(_WIN32)
#define __WIN32
#define __WIN32__
#endif

#undef __wur

#undef _ACRTIMP
#undef _CRTIMP
#undef __WINE_UUID_ATTR

#undef S_ISUID
#undef S_ISGID
#undef S_ISVTX

#undef __WATCOMC__
#undef _SCO_DS
#undef __osf__

typedef __builtin_wchar_t wchar_t;
typedef __builtin_char8_t char8_t;
typedef __builtin_char16_t char16_t;
typedef __builtin_char32_t char32_t;
#define _WCHAR_T_DEFINED

#undef SSIZE_MAX

/* In /usr/include/wine/windows/poppack.h pack(4) is used for __SUNPRO_CC,
 * which makes the program much slower. */
#undef __SUNPRO_CC

#undef WINAPIV
#undef __RCSID
#undef __COMPAR_FN_T

#undef FAR
#undef SMALL_MEDIUM
#undef SYS16BIT
#ifndef _WIN32
#undef UNDER_CE
#endif

#undef _CRT_NO_POSIX_ERROR_CODES

#define __FLT_DIG__ 6
#define __DBL_DIG__ 15
#define __LDBL_DIG__ 18

// Prevent winnt.h from defining DELETE, because it breaks http-parser
#lockdefine DELETE

// Prevent wine from defining __declspec, because those headers are only sometimes included before __declspec is used
#lockdefine __declspec

#lockdefine NDEBUG

#undef _WIN32_WINNT0000
#undef NTDDI_VERSION

#undef NETWARE

#undef _Static_assert
#lockdefine _Static_assert

#undef assert

// https://clang.llvm.org/docs/LanguageExtensions.html
#define __has_builtin(x) __has_builtin_ ## x
#define __has_feature(x) __has_feature_ ## x
#define __has_extension(x) __has_extension_ ## x
#define __has_cpp_attribute(x) __has_cpp_attribute_ ## x
#define __has_c_attribute(x) __has_c_attribute_ ## x
#define __has_attribute(x) __has_attribute_ ## x
#define __has_declspec_attribute(x) __has_declspec_attribute_ ## x
#define __is_identifier(x) __is_identifier ## x

#undef __int8
#lockdefine __int8
#undef __int16
#lockdefine __int16
#undef __int32
#lockdefine __int32
#undef __int64
#lockdefine __int64

#define __has_include(f) 1
