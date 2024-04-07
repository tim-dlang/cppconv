module testdefines66;

import config;
import cppconvhelpers;

/+ #define wxDECLARE_EVENT_TABLE() \
    int f(); \
    int g() +/
extern(D) alias wxDECLARE_EVENT_TABLE = function string()
{
    return
            mixin(interpolateMixin(q{int f();
            int g();}));
};

extern(C++, class) struct wxFrame
{
private:
    mixin(wxDECLARE_EVENT_TABLE());
}

