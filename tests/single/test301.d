
module test301;

import config;
import cppconvhelpers;

/+ namespace N {
inline bool f() noexcept;
} +/

bool f()/+ noexcept+/
{
    return true;
}

