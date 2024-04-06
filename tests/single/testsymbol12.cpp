template <typename T>
class QList
{
public:
    struct Node {
    };

    void node_destruct(Node *n);
    void node_destruct(Node *from, Node *to);
    void dealloc();
};

template <typename T>
void QList<T>::node_destruct(Node *n)
{
// comment1
}

template <typename T>
void QList<T>::node_destruct(Node *from, Node *to)
{
// comment2
}

template <typename T>
void QList<T>::dealloc()
{
    node_destruct(0,
                  0);
}
