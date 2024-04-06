module testconflict_tl_f_3;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
extern(C++, class) struct C(T)
{
public:
	enum {
		isLarge = (T.sizeof>(void*).sizeof),
		isStatic = true
	}
}
alias X = int;
}
static if (!defined!"DEF")
{
__gshared int C;
 __gshared int X;
  __gshared int isLarge;
   __gshared int isStatic;
}

void f(T)()
{
	if( mixin((defined!"DEF") ? q{
        	C!(X).isLarge || C!(X).isStatic
    	} : q{
        C<X>.isLarge||C<X>.isStatic
    	}))
	{}
}

