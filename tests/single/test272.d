
module test272;

import config;
import cppconvhelpers;

extern(C++, class) struct QFileDevice
{
public:
    enum Permission {
        ReadOwner = 0x4000, WriteOwner = 0x2000, ExeOwner = 0x1000,
    }
}

extern(C++, class) struct QFile
{
    public QFileDevice base0;
    alias base0 this;
}

extern(C++, class) struct QFileInfo
{
public:
    bool permission(QFile.Permission permission) const;
    QFile.Permission permissions() const;
}

