template <typename T>
class QList
{
};

template <typename InputIterator,
          typename ValueType = typename InputIterator::value_type>
QList(InputIterator, InputIterator) -> QList<ValueType>;
