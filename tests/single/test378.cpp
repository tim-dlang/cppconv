class FileNotFound;

class QPdfDocument
{
public:
    enum class Status {
        Null,
        Loading,
        Ready,
        Unloading,
        Error
    };

    enum class Error {
        None,
        Unknown,
        DataNotYetAvailable,
        FileNotFound,
        InvalidFileFormat,
        IncorrectPassword,
        UnsupportedSecurityScheme
    };

    Error load();

    Status status() const;
};

QPdfDocument::Status s1 = QPdfDocument::Status::Ready;
QPdfDocument::Error e1 = QPdfDocument::Error::Unknown;
