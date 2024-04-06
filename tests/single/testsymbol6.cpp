namespace Qt
{
    enum CaseSensitivity {
        CaseInsensitive,
        CaseSensitive
    };
}

class QStringList
{
    inline bool contains(Qt::CaseSensitivity cs = Qt::CaseSensitive) const;
};
