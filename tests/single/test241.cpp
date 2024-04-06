
template <typename T>
inline T qAbs(const T &t) { return t >= 0 ? t : -t; }

static inline bool qFuzzyIsNull(double d)
{
    return qAbs(d) <= 0.000000000001;
}

static inline bool qFuzzyIsNull(float f)
{
    return qAbs(f) <= 0.00001f;
}
