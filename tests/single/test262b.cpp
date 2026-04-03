
const char *qFlagLocation(const char *method);

#define QT_STRINGIFY2(x) #x
#define QT_STRINGIFY(x) QT_STRINGIFY2(x)

# define QT_STRINGIFY_SIGNAL(a) "2" #a

# ifndef QT_NO_DEBUG
#  define QLOCATION "\0" __FILE__ ":" QT_STRINGIFY(__LINE__)
#  define SLOT(a)     qFlagLocation("1"#a QLOCATION)
#  define SIGNAL(a)   qFlagLocation(QT_STRINGIFY_SIGNAL(a) QLOCATION)
# else
#  define SLOT(a)     "1"#a
#  define SIGNAL(a)   QT_STRINGIFY_SIGNAL(a)
# endif

class QObject
{
public:
    static void connect(const QObject *sender, const char *signal,
                        const QObject *receiver, const char *member);
};

void f(QObject *a, QObject *b)
{
	QObject::connect(a, SIGNAL(signalVoid()), b, SLOT(onSignalVoid()));
}
