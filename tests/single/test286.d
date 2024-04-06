module test286;

import config;
import cppconvhelpers;

/+ #define Q_DECL_DEPRECATED __attribute__ ((__deprecated__))
#define Q_DECL_DEPRECATED_X(text) __attribute__ ((__deprecated__(text)))

#ifdef DEF
#define QT_DEPRECATED Q_DECL_DEPRECATED
#define QT_DEPRECATED_X(text) Q_DECL_DEPRECATED_X(text)
#else
#define QT_DEPRECATED
#define QT_DEPRECATED_X(text)
#endif +/

/+ Q_DECL_DEPRECATED +/ void f1();
/+ Q_DECL_DEPRECATED_X("Use something else") +/ void f2();
/+ QT_DEPRECATED +/ void f3();
/+ QT_DEPRECATED_X("Use something else") +/ void f4();

