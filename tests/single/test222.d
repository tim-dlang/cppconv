module test222;

import config;
import cppconvhelpers;

extern(C++, class) struct QFlags(Enum)
{

}

/+ #define Q_DECLARE_FLAGS(Flags, Enum)\
typedef QFlags<Enum> Flags; +/

extern(C++, class) struct QTextStream
{
private:
    enum NumberFlag {
        ShowBase = 0x1,
        ForcePoint = 0x2,
        ForceSign = 0x4,
        UppercaseBase = 0x8,
        UppercaseDigits = 0x10
    }
    /+ Q_DECLARE_FLAGS(NumberFlags, NumberFlag) +/
alias NumberFlags = QFlags!(NumberFlag);}

