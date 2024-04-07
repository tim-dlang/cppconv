module test257;

import config;
import cppconvhelpers;

extern(C++, class) struct QList(T)
{
private:
    struct Node { void* v;
    }

    Node* detach_helper_grow(int i, int c)
    {
        return null;
    }

    alias size_type = int;
    alias iterator = T*;

    iterator insert(iterator before, int n, ref const(T) t)
    /+iterator insert(iterator before, size_type n, ref const(T) t)+/
    {
    }
}


