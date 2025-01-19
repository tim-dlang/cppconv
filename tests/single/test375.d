module test375;

import config;
import cppconvhelpers;

extern(C++, class) struct QList(T)
{
}

/+ template <typename InputIterator,
          typename ValueType = typename InputIterator::value_type>
QList(,) -> QList<ValueType>; +/

