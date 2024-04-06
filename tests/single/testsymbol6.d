module testsymbol6;

import config;
import cppconvhelpers;

extern(C++, "Qt")
{
    enum CaseSensitivity {
        CaseInsensitive,
        CaseSensitive
    }
}

extern(C++, class) struct QStringList
{
private:
    pragma(inline, true) bool contains(/+ Qt:: +/CaseSensitivity cs = /+ Qt:: +/CaseSensitivity.CaseSensitive) const;
}

