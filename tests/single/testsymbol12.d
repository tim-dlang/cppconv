module testsymbol12;

import config;
import cppconvhelpers;

extern(C++, class) struct QList(T)
{
public:
    struct Node {
    }

    void node_destruct(Node* n)
    {
    // comment1
    }
    void node_destruct(Node* from, Node* to)
    {
    // comment2
    }
    void dealloc()
    {
        node_destruct(null,
                      null);
    }
}

