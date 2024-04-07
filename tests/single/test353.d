module test353;

import config;
import cppconvhelpers;

static if (defined!"QT_NO_VALIDATOR")
{
extern(C++, class) struct QValidator;
}


static if (!defined!"QT_NO_VALIDATOR")
{
extern(C++, class) struct QValidator
{
public:
    enum State {
        Invalid,
        Intermediate,
        Acceptable
    }
}
}

class QAbstractSpinBox
{
public:
    /+ virtual +/ QValidator.State validate() const;
}

