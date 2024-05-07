
struct RegisterInterface {
    int version;

    int typeId;
    int listId;

    const char *uri;
    int versionMajor;
};

template <typename T>
int qRegisterNormalizedMetaType(int i)
{
    return i;
}

template<typename T>
class QQmlListProperty {
};

template<typename T>
int qmlRegisterInterface(const char *typeName)
{
    RegisterInterface qmlInterface = {
        1,

        qRegisterNormalizedMetaType<T *>(1),
        qRegisterNormalizedMetaType<QQmlListProperty<T> >(1),

        "",
        0
    };
}
