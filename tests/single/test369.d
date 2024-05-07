
module test369;

import config;
import cppconvhelpers;

struct RegisterInterface {
    int version_;

    int typeId;
    int listId;

    const(char)* uri;
    int versionMajor;
}

int qRegisterNormalizedMetaType(T)(int i)
{
    return i;
}

extern(C++, class) struct QQmlListProperty(T) {
}

int qmlRegisterInterface(T)(const(char)* typeName)
{
    RegisterInterface qmlInterface = RegisterInterface(
        1,

        qRegisterNormalizedMetaType!(T*)(1),
        qRegisterNormalizedMetaType!(QQmlListProperty!(T)) (1),

        "".ptr,
        0)
    ;
}

