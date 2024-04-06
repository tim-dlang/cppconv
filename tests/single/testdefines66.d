module testdefines66;

import config;
import cppconvhelpers;

/+ #define wxDECLARE_EVENT_TABLE() \
    int f(); \
    int g() +/

extern(C++, class) struct wxFrame
{
private:
    /+ wxDECLARE_EVENT_TABLE() +/int f();int g();
}

