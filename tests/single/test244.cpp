typedef unsigned short ushort;

class QChar {
public:
    QChar(short rc) noexcept : ucs(ushort(rc)) {} // implicit

    ushort ucs;
};
