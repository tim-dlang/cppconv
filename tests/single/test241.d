
module test241;

import config;
import cppconvhelpers;

pragma(inline, true) T qAbs(T)(ref const(T) t) { return t >= 0 ? t : -t; }

pragma(inline, true) bool qFuzzyIsNull(double d)
{
    return qAbs(d) <= 0.000000000001;
}

pragma(inline, true) bool qFuzzyIsNull(float f)
{
    return qAbs(f) <= 0.00001f;
}

