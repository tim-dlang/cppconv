#define QT_DEPRECATED_X(x)
#undef Q_QDOC

#ifdef Q_QDOC
typedef void* LessThan;
template <typename T> LessThan qLess();
template <typename T> LessThan qGreater();
#else
template <typename T>
class QT_DEPRECATED_X("Use std::less") qLess
{
public:
    inline bool operator()(const T &t1, const T &t2) const
    {
        return (t1 < t2);
    }
};
#endif
