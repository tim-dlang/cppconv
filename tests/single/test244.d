module test244;

import config;
import cppconvhelpers;

// self alias: alias ushort_ = ushort;

extern(C++, class) struct QChar {
public:
    this(short rc)/+ noexcept+/
    {
        this.ucs = ushort(rc);
    } // implicit

    ushort ucs;
}

