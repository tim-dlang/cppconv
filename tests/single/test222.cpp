template<typename Enum>
class QFlags
{

};

#define Q_DECLARE_FLAGS(Flags, Enum)\
typedef QFlags<Enum> Flags;

class QTextStream
{
    enum NumberFlag {
        ShowBase = 0x1,
        ForcePoint = 0x2,
        ForceSign = 0x4,
        UppercaseBase = 0x8,
        UppercaseDigits = 0x10
    };
    Q_DECLARE_FLAGS(NumberFlags, NumberFlag)
};
