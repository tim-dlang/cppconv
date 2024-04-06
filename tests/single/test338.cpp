
namespace Qt {
    enum TimerType {
        PreciseTimer,
        CoarseTimer,
        VeryCoarseTimer
    };
}

class QDeadlineTimer
{
public:
    Qt::TimerType timerType() const noexcept
    { return Qt::TimerType(type & 0xff); }

private:
    unsigned type;
};
