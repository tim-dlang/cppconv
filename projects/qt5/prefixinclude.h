#undef __OBJC__

#define __cplusplus 201500
#define __cpp_constexpr 201907L
#define __cpp_exceptions 199711
#undef __cpp_deduction_guides

#undef QT_NAMESPACE
#undef QT_STATIC
#define QT_SHARED
#undef QT_BOOTSTRAPPED
#undef Q_DECL_CONST_FUNCTION
#undef Q_DECL_UNUSED
#undef QT_NO_EXCEPTIONS
#undef Q_DECL_PURE_FUNCTION
#undef Q_DECL_COLD_FUNCTION
#undef QT_BUILD_CORE_LIB
#undef Q_NORETURN
#undef Q_DECL_IMPORT
#undef QT_NO_DEPRECATED
#undef QT_DISABLE_DEPRECATED_BEFORE
#undef QT_NO_KEYWORDS
#undef Q_OUTOFLINE_TEMPLATE
#undef Q_ASSERT
#undef QT_NO_JAVA_STYLE_ITERATORS
#undef QT_INCLUDE_COMPAT
#undef QT_NO_QOBJECT
#undef Q_NO_TYPESAFE_FLAGS
#undef QT_NEEDS_QMAIN
#undef Q_QDOC
#undef QT_COORD_TYPE
#undef Q_MOC_RUN
#undef Q_FORWARD_DECLARE_OBJC_CLASS
#undef Q_FORWARD_DECLARE_CF_TYPE
#undef QT_NO_META_MACROS
#undef Q_DECL_DEPRECATED
#define Q_COMPILER_STATIC_ASSERT

#define Q_DECL_CONSTEXPR constexpr
#lockdefine Q_DECL_CONSTEXPR
#define Q_COMPILER_CONSTEXPR

#undef __CORRECT_ISO_CPP_MATH_H_PROTO
#undef _NODE_HANDLE

#undef _INITIALIZER_LIST

// See also:
// /usr/include/qt/QtCore/qobjectdefs.h
// https://git.sailfishos.org/mer-core/qtbase/commit/6c54e10144e7af02f4c35e20e5f375a0cf280b8b
// https://code.woboq.org/woboq/mocng/src/qobjectdefs-injected.h.html
# define QT_ANNOTATE_ACCESS_SPECIFIER(x) __cppconv_##x

# define QT_ANNOTATE_CLASS(type, ...)
# define QT_ANNOTATE_CLASS2(type, a1, a2)
# define QT_ANNOTATE_FUNCTION(x) __cppconv_##x

#undef QT_NO_SIGNALS_SLOTS_KEYWORDS

#if defined(_WIN32)
// From ../../wine/orig/include/msvcrt/corecrt.h, because Qt uses _WIN64 without always including corecrt.h.
#if (defined(__x86_64__) || defined(__powerpc64__) || defined(__aarch64__))
#define _WIN64
#endif
#endif

#define Q_ALIGNOF  alignof
#lockdefine Q_ALIGNOF

#undef QT_NO_EMIT

#define Q_UNLIKELY
#lockdefine Q_UNLIKELY
#define Q_LIKELY
#lockdefine Q_LIKELY
#define Q_UNUSED(x)
#lockdefine Q_UNUSED

#define Q_STATIC_ASSERT(Condition) static_assert(Condition)
#lockdefine Q_STATIC_ASSERT
#define Q_STATIC_ASSERT_X(Condition, Message) static_assert(bool(Condition), Message)
#lockdefine Q_STATIC_ASSERT_X

#include <assert.h>
#define Q_ASSERT(cond) assert(cond)
#lockdefine Q_ASSERT
#define Q_ASSERT_X(cond, where, what) assert(cond)
#lockdefine Q_ASSERT_X

#undef QT_BASIC_ATOMIC_HAS_CONSTRUCTORS
#lockdefine QT_BASIC_ATOMIC_HAS_CONSTRUCTORS

#undef QT_STRICT_ITERATORS
#undef QT_NO_EXCEPTIONS
#lockdefine QT_NO_EXCEPTIONS

#    define Q_BYTE_ORDER __BYTE_ORDER__
#lockdefine Q_BYTE_ORDER

#define Q_DECLARE_TYPEINFO(TYPE, FLAGS) __cppconv_qt_typeinfo(TYPE, FLAGS)
#lockdefine Q_DECLARE_TYPEINFO

#  define Q_DECL_EXPORT __declspec(dllexport)
#  define Q_DECL_IMPORT __declspec(dllimport)
#lockdefine Q_DECL_EXPORT
#lockdefine Q_DECL_IMPORT

#define Q_WINSTRICT
#undef HINSTANCE
#undef HDC
#undef HWND
#undef HFONT
#undef HPEN
#undef HBRUSH
#undef HBITMAP
#undef HICON
#undef HCURSOR
#undef HPALETTE
#undef HRGN
#undef HMONITOR
#undef _HRESULT_DEFINED

#undef Q_FORWARD_DECLARE_CG_TYPE
#undef Q_FORWARD_DECLARE_MUTABLE_CG_TYPE
#undef Q_FORWARD_DECLARE_CF_TYPE
#undef Q_FORWARD_DECLARE_MUTABLE_CF_TYPE

#undef Q_FULL_TEMPLATE_INSTANTIATION
#lockdefine Q_FULL_TEMPLATE_INSTANTIATION

#define Q_INLINE_TEMPLATE inline
#lockdefine Q_INLINE_TEMPLATE

template<int> struct QIntegerForSize
{
	typedef IntentionallyUnknownType Unsigned;
	typedef IntentionallyUnknownType Signed;
};

#undef Q_COMPILER_UNIFORM_INIT
#lockdefine Q_COMPILER_UNIFORM_INIT

#lockdefine Q_COMPILER_THREADSAFE_STATICS

#  define Q_INT64_C(c) c ## i64    /* signed 64 bit constant */
#  define Q_UINT64_C(c) c ## ui64   /* unsigned 64 bit constant */
#lockdefine Q_INT64_C
#lockdefine Q_UINT64_C

#undef Q_MAP_DEBUG

#define Q_DECL_DEPRECATED __attribute__ ((__deprecated__))
#define Q_DECL_DEPRECATED_X(text) __attribute__ ((__deprecated__(text)))
#lockdefine Q_DECL_DEPRECATED
#lockdefine Q_DECL_DEPRECATED_X
#define QT_DEPRECATED_WARNINGS_SINCE 0xffffff
#undef QT_NO_DEPRECATED_WARNINGS

#define Q_DECL_CONST_FUNCTION __attribute__((const))
#lockdefine Q_DECL_CONST_FUNCTION

#undef Q_NO_TEMPLATE_FRIENDS
#lockdefine Q_NO_TEMPLATE_FRIENDS

#define Q_ATTRIBUTE_FORMAT_PRINTF(A, B)
#lockdefine Q_ATTRIBUTE_FORMAT_PRINTF

#undef Q_CLANG_QDOC
#define QT_NO_DEBUG
#define QT_NO_DEBUG_STREAM

#undef Q_COMPILER_VARIADIC_TEMPLATES
#undef __cpp_variable_templates

#  define QT_MAKE_CHECKED_ARRAY_ITERATOR(x, N) (x)

#unknown Q_PROCESSOR_WORDSIZE
#lockdefine Q_PROCESSOR_WORDSIZE

#undef Q_STDLIB_UNICODE_STRINGS
#lockdefine Q_STDLIB_UNICODE_STRINGS

#define Q_COMPILER_UNICODE_STRINGS

#define Q_ALLOC_SIZE(x)
#lockdefine Q_ALLOC_SIZE

#  define Q_BASIC_ATOMIC_INITIALIZER(a)     { a }
#lockdefine Q_BASIC_ATOMIC_INITIALIZER

#undef tagMSG

#unknown QT_STRINGVIEW_LEVEL

#define QT_NO_CAST_TO_ASCII
#define QT_NO_CAST_FROM_ASCII

#undef __cpp_init_captures
#undef __cpp_generic_lambdas
#undef __cpp_lib_invoke
#undef __has_cpp_attribute_nodiscard

#undef QT_CRYPTOGRAPHICHASH_ONLY_SHA1
#undef QT_SHA3_KECCAK_COMPAT

#define Q_DECLARE_SHARED_NOT_MOVABLE_UNTIL_QT6(TYPE) \
                               Q_DECLARE_SHARED_IMPL(TYPE, Q_RELOCATABLE_TYPE)
#lockdefine Q_DECLARE_SHARED_NOT_MOVABLE_UNTIL_QT6

#undef QT_COMPILING_QIMAGE_COMPAT_CPP
#undef QT_COMPILING_QSTRING_COMPAT_CPP
#define Q_COMPILER_REF_QUALIFIERS

#define Q_REQUIRED_RESULT [[nodiscard]]
#lockdefine Q_REQUIRED_RESULT

#define __cpp_char8_t

#undef __cpp_lib_bitops
#define QT_HAS_BUILTIN_CTZ
#define QT_HAS_BUILTIN_CTZS
#define QT_HAS_BUILTIN_CTZLL

#undef QT_NO_SSL
