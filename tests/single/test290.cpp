#ifdef DEF
#ifdef _WIN32
#    define Q_DECL_DEPRECATED_X(text) __declspec(deprecated(text))
#else
#      define Q_DECL_DEPRECATED_X(text) __attribute__ ((__deprecated__(text)))
#endif
#else
#      define Q_DECL_DEPRECATED_X(text)
#endif

Q_DECL_DEPRECATED_X(R"(Use u"~~~" or QStringView(u"~~~") instead of QStringViewLiteral("~~~"))")
void f();
