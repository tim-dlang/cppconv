class QValidator;

#ifndef QT_NO_VALIDATOR
class QValidator
{
public:
    enum State {
        Invalid,
        Intermediate,
        Acceptable
    };
};
#endif

class QAbstractSpinBox
{
public:
    virtual QValidator::State validate() const;
};
