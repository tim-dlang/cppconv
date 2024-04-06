
module test338;

import config;
import cppconvhelpers;

extern(C++, "Qt") {
    enum TimerType {
        PreciseTimer,
        CoarseTimer,
        VeryCoarseTimer
    }
}

extern(C++, class) struct QDeadlineTimer
{
public:
    /+ Qt:: +/TimerType timerType() const/+ noexcept+/
    { return cast(/+ Qt:: +/TimerType) (type & 0xff); }

private:
    uint type;
}

