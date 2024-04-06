template <typename T>
class QList
{
private:
    struct Node { void *v;
    };

    Node *detach_helper_grow(int i, int n);

    typedef int size_type;
    typedef T *iterator;

    iterator insert(iterator before, int n, const T &x);
};

template <typename T>
typename QList<T>::Node *QList<T>::detach_helper_grow(int i, int c)
{
    return 0;
}

template <typename T>
typename QList<T>::iterator QList<T>::insert(iterator before, size_type n, const T &t)
{
};
