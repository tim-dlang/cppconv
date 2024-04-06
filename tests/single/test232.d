module test232;

import config;
import cppconvhelpers;

extern(C++, class) struct QLatin1String
{
public:
    alias value_type = const(char);
    alias reference = ref value_type;
    alias const_reference = reference;
    alias iterator = value_type*;
    alias const_iterator = iterator;
    alias difference_type = int;
    alias size_type = int;
}

