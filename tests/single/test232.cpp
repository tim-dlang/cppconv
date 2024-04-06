class QLatin1String
{
public:
    using value_type = const char;
    using reference = value_type&;
    using const_reference = reference;
    using iterator = value_type*;
    using const_iterator = iterator;
    using difference_type = int;
    using size_type = int;
};
