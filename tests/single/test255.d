module test255;

import config;
import cppconvhelpers;

static if (!defined!"DEF")
{
extern(C++, class) struct QAction;
}


static if (defined!"DEF")
{
class QAction
{
public:
	/+ virtual +/~this();
}
}

void f(Identity!(mixin((defined!"DEF")?q{QAction}:q{QAction*})) a);

