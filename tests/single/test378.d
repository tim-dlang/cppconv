module test378;

import config;
import cppconvhelpers;

extern(C++, class) struct FileNotFound;

extern(C++, class) struct QPdfDocument
{
public:
    enum /+ class +/ Status {
        Null,
        Loading,
        Ready,
        Unloading,
        Error
    }

    enum /+ class +/ Error {
        None,
        Unknown,
        DataNotYetAvailable,
        FileNotFound,
        InvalidFileFormat,
        IncorrectPassword,
        UnsupportedSecurityScheme
    }

    Error load();

    Status status() const;
}

__gshared QPdfDocument.Status s1 = QPdfDocument.Status.Ready;
__gshared QPdfDocument.Error e1 = QPdfDocument.Error.Unknown;

