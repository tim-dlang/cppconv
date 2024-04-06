typedef unsigned long size_t;

struct QArrayData
{
    int size;
    unsigned int alloc : 31;
    unsigned int capacityReserved : 1;

    long offset; // in bytes from beginning of header

    void *data()
    {
        if(size == 0
                || offset < 0 || size_t(offset) >= sizeof(QArrayData))
		{}
        return reinterpret_cast<char *>(this) + offset;
    }
};
