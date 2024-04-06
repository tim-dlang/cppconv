
module test283;

import config;
import cppconvhelpers;

extern(C++, class) struct QVector2D
{
public:
    @disable this();
    pragma(mangle, defaultConstructorMangling(__traits(identifier, typeof(this))))
    void rawConstructor();
    static typeof(this) create()
    {
        typeof(this) r = typeof(this).init;
        r.rawConstructor();
        return r;
    }

    pragma(inline, true) this(float xpos, float ypos)
    {
        this.v = [xpos, ypos];
    }
private:
    float[2] v;
}


