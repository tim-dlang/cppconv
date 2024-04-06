module test307;

import config;
import cppconvhelpers;

struct QMetaObject
{
    enum Call {
        InvokeMetaMethod,
        ReadProperty,
        WriteProperty,
        ResetProperty,
        QueryPropertyDesignable,
        QueryPropertyScriptable,
        QueryPropertyStored,
        QueryPropertyEditable,
        QueryPropertyUser,
        CreateInstance,
        IndexOfMethod,
        RegisterPropertyMetaType,
        RegisterMethodArgumentMetaType
    }
}

class QObject
{
private:
	/+ virtual +/ int qt_metacall(QMetaObject.Call, int, void** );
}

extern(C++, "QtPrivate") {
    /* Trait that tells is a the Object has a Q_OBJECT macro */
    struct HasQ_OBJECT_Macro(Object) {
        /+ template <typename T> +/
        static char test(T)(int function(QMetaObject.Call, int, void** )/+ T::* +/ );
        static int test(int function(QMetaObject.Call, int, void** )/+ Object::* +/ );
        enum { Value =  (test(&Object.qt_metacall)). sizeof == int.sizeof }
    }
}

