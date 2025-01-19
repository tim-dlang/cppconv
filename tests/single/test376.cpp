typedef unsigned size_t;

template <size_t Size, size_t Align, size_t Prealloc>
class QVLAStorage
{
    alignas(Align) char array[Prealloc * (Align > Size ? Align : Size)];

    static_assert(sizeof(array));
};
