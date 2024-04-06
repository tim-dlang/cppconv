module test207;

import config;
import cppconvhelpers;

/+ #define QT_FOR_EACH_STATIC_EASINGCURVE(F)\
	F(QEasingCurve, 29, QEasingCurve)

#define QT_FOR_EACH_STATIC_CORE_CLASS(F)\
	F(QChar, 7, QChar) \
	QT_FOR_EACH_STATIC_EASINGCURVE(F)


#define QT_FORWARD_DECLARE_STATIC_TYPES_ITER(TypeName, TypeId, Name) \
    class Name; +/
extern(C++, class) struct QChar;
extern(C++, class) struct QEasingCurve;

/+ QT_FOR_EACH_STATIC_CORE_CLASS(QT_FORWARD_DECLARE_STATIC_TYPES_ITER) +/
