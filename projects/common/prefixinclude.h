
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
#regex_undef "Q_PROCESSOR_.*"
#regex_undef ".*_H___"

#undef __WINE_INTERNAL_POPPACK

#unknown CPPCONV_OS
#alias CPPCONV_OS_LINUX CPPCONV_OS == 1
#alias CPPCONV_OS_WIN CPPCONV_OS == 2
#alias CPPCONV_OS_MACOS CPPCONV_OS == 3
#alias CPPCONV_OS_IOS CPPCONV_OS == 4
#alias CPPCONV_OS_TVOS CPPCONV_OS == 5
#alias CPPCONV_OS_WATCHOS CPPCONV_OS == 6
#alias CPPCONV_OS_BSD CPPCONV_OS == 7
#alias __gnu_hurd__ CPPCONV_OS == 8
#alias __WEBOS__ CPPCONV_OS == 9
#alias __sun CPPCONV_OS == 10
#alias __hpux CPPCONV_OS == 11
#alias __INTERIX CPPCONV_OS == 12
#alias _AIX CPPCONV_OS == 13
#alias __Lynx__ CPPCONV_OS == 14
#alias __QNXNTO__ CPPCONV_OS == 15
#alias __INTEGRITY CPPCONV_OS == 16
#alias __VXWORKS__ CPPCONV_OS == 17
#alias __HAIKU__ CPPCONV_OS == 18
#alias __EMSCRIPTEN__ CPPCONV_OS == 19
#alias __native_client__ CPPCONV_OS == 20
#alias __minix CPPCONV_OS == 21
#alias __MSDOS__ CPPCONV_OS == 22
#alias __OS400__ CPPCONV_OS == 23
#alias __OS2__ CPPCONV_OS == 24
#alias __VMS CPPCONV_OS == 25
#alias __MVS__ CPPCONV_OS == 26

#if defined(CPPCONV_OS_LINUX) || defined(CPPCONV_OS_BSD) || defined(__EMSCRIPTEN__) \
    || defined(_AIX) || defined(__HAIKU__) || defined(__gnu_hurd__) || defined(__sun)
#imply defined(__unix)
#endif

#unknown CPPCONV_POINTER_SIZE
#unknown CPPCONV_ARCH
#alias CPPCONV_ARCH_X86 CPPCONV_ARCH == 1
#alias CPPCONV_ARCH_POWERPC CPPCONV_ARCH == 2
#alias CPPCONV_ARCH_ARM CPPCONV_ARCH == 3
#alias __avr32__ CPPCONV_ARCH == 4
#alias __bfin__ CPPCONV_ARCH == 5
#alias __ia64__ CPPCONV_ARCH == 6
#alias __mips__ CPPCONV_ARCH == 7
#alias __riscv CPPCONV_ARCH == 8
#alias __s390__ CPPCONV_ARCH == 9
#alias __sh__ CPPCONV_ARCH == 10
#alias __sparc__ CPPCONV_ARCH == 11
#alias CPPCONV_ARCH_EMSCRIPTEN CPPCONV_ARCH == 11

#undef i386
#undef __i386
#undef __i386__
#undef _M_IX86
#ifdef _X86_
#define i386 1
#define __i386 1
#define __i386__ 1
#define _X86_ 1
#define _M_IX86 1
#imply defined(CPPCONV_ARCH_X86)
#imply CPPCONV_POINTER_SIZE == 32
#endif

#undef __amd64__
#undef __amd64
#undef __x86_64
#undef _M_AMD64
#undef _M_X64
#ifdef __x86_64__
#define __amd64__ 1
#define __amd64 1
#define __x86_64__ 1
#define _M_AMD64 1
#define _M_X64 1
#imply defined(CPPCONV_ARCH_X86)
#endif

#if defined(__SSE2__) || defined(__SSE3__) || defined(__SSSE3__) || defined(__SSE4_1__) || defined(__SSE4_2__) || defined(__AVX__)
#imply defined(CPPCONV_ARCH_X86)
#endif

#undef __powerpc
#undef __powerpc__
#undef __powerpc64__
#undef __POWERPC__
#undef __ppc__
#undef __ppc64__
#undef __PPC__
#undef __PPC64__
#undef _ARCH_PPC
#undef _ARCH_PPC64
#undef _M_PPC
#ifdef CPPCONV_ARCH_POWERPC
#define __powerpc 1
#define __powerpc__ 1
#define __powerpc64__ 1
#define __POWERPC__ 1
#define __ppc__ 1
#define __ppc64__ 1
#define __PPC__ 1
#define __PPC64__ 1
#define _ARCH_PPC 1
#define _ARCH_PPC64 1
#define _M_PPC 1
#endif

#undef _M_ARM
#ifdef __arm__
#unknown _M_ARM
#imply defined(CPPCONV_ARCH_ARM)
#endif

#ifdef __thumb__
#imply defined(CPPCONV_ARCH_ARM)
#endif

#undef _M_ARM64
#undef __ARM64__
#ifdef __aarch64__
#unknown _M_ARM64
#define __ARM64__ 1
#imply defined(CPPCONV_ARCH_ARM)
#endif

#undef __ia64
#undef _M_IA64
#ifdef __ia64__
#define __ia64 1
#define _M_IA64 1
#endif

#undef __mips
#undef _M_MRX000
#ifdef __mips__
#unknown __mips
#unknown _M_MRX000
#endif

#ifdef __EMSCRIPTEN__
#imply defined(CPPCONV_ARCH_EMSCRIPTEN)
#endif
#ifndef __EMSCRIPTEN__
#imply !defined(CPPCONV_ARCH_EMSCRIPTEN)
#endif

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

#undef WIN32
#undef _WIN32
#undef __WIN32__
#ifdef CPPCONV_OS_WIN
/*#if CPPCONV_POINTER_SIZE == 16
#define _WIN16
#endif*/
#define WIN32 1
#define _WIN32 1
#define __WIN32__ 1
#endif

#undef WIN64
#undef _WIN64
#ifdef __WIN64__
#define WIN64 1
#define _WIN64 1
#define __WIN64__ 1
#imply defined(CPPCONV_OS_WIN)
#imply CPPCONV_POINTER_SIZE == 64
#endif
#if defined(__CYGWIN__) || defined(__NT__)
#imply defined(CPPCONV_OS_WIN)
#endif

#undef __linux__
#undef __linux
#ifdef CPPCONV_OS_LINUX
#define __linux__
#define __linux
#endif

#undef ANDROID
#ifdef __ANDROID__
#define ANDROID 1
#endif

#if defined(ANDROID) || defined(__ANDROID__) || defined(__WEBOS__)
#imply defined(CPPCONV_OS_LINUX)
#endif

#if defined(__FreeBSD__) || defined(__DragonFly__) || defined(__FreeBSD_kernel__) \
    || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__MidnightBSD__) || defined(__bsdi__)
#imply defined(CPPCONV_OS_BSD)
#endif

#undef sun
#ifdef __sun
#define sun 1
#endif

#undef EMSCRIPTEN
#ifdef __EMSCRIPTEN__
#define EMSCRIPTEN 1
#endif

#undef hpux
#undef _hpux
#ifdef __hpux
#define hpux 1
#define _hpux 1
#endif

#undef __unix
#ifdef __unix__
#define __unix 1
#endif

#ifdef __gnu_hurd__
#imply defined(__GNU__)
#endif

#undef MSDOS
#undef _MSDOS
#undef __DOS__
#ifdef __MSDOS__
#define MSDOS 1
#define _MSDOS 1
#define __DOS__ 1
#endif

#undef OS2
#undef _OS2
#undef __TOS_OS2__
#undef OS_2
#ifdef __OS2__
#define OS2 1
#define _OS2 1
#define __TOS_OS2__ 1
#define OS_2 1
#endif

#undef VMS
#ifdef __VMS
#define VMS 1
#endif

#undef VXWORKS
#undef __vxworks
#ifdef __VXWORKS__
#define VXWORKS 1
#define __vxworks 1
#endif

#undef __HOS_MVS__
#undef __TOS_MVS__
#ifdef __MVS__
#define __HOS_MVS__ 1
#define __TOS_MVS__ 1
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

#unknown __BYTE_ORDER__
#define __ORDER_BIG_ENDIAN__ 4321
#define __ORDER_LITTLE_ENDIAN__ 1234
#define __ORDER_PDP_ENDIAN__ 3412
#alias __BIG_ENDIAN__ __BYTE_ORDER__ == 4321
#alias __LITTLE_ENDIAN__ __BYTE_ORDER__ == 1234

#undef WORDS_BIGENDIAN
#ifdef __BIG_ENDIAN__
#define WORDS_BIGENDIAN
#endif
#lockdefine WORDS_BIGENDIAN
