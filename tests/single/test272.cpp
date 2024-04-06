
class QFileDevice
{
public:
    enum Permission {
        ReadOwner = 0x4000, WriteOwner = 0x2000, ExeOwner = 0x1000,
    };
};

class QFile : public QFileDevice
{
};

class QFileInfo
{
public:
    bool permission(QFile::Permission permission) const;
    QFile::Permission permissions() const;
};
