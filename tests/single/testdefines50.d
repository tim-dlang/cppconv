module testdefines50;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
void write_impl(const(char)* s);
void write_impl_debug(const(char)* s, const(char)* file, int line);
/+ #define write write_impl +/
alias write = write_impl;
/+ #define write2(s) write_impl(s) +/
extern(D) alias write2 = function string(string s)
{
    return mixin(interpolateMixin(q{write_impl($(s))}));
};
/+ #define write3(s) write_impl_debug(s, __FILE__, __LINE__) +/
extern(D) alias write3 = function string(string s)
{
    return mixin(interpolateMixin(q{write_impl_debug($(s), __FILE__, __LINE__)}));
};
}
static if (!defined!"DEF")
{
void write(const(char)* s);
void write2(const(char)* s);
void write3(const(char)* s);
}

void f()
{
	mixin((defined!"DEF") ? q{
        	write
    	} : q{
        write
    	})("test");
	(mixin((defined!"DEF") ? q{
        	(mixin(write2(q{"test"})))
    	} : q{
        write2("test")
    	}));
	(mixin((defined!"DEF") ? q{
        	(mixin(write3(q{"test"})))
    	} : q{
        write3("test")
    	}));
}
void g(const(char)* str)
{
	mixin((defined!"DEF") ? q{
        	write
    	} : q{
        write
    	})(str);
	static if (defined!"DEF")
	{
    	(mixin(write2(q{str})));
	}
	else
	{
    write2(str);
	}
	static if (defined!"DEF")
	{
    	(mixin(write3(q{str})));
	}
	else
	{
    write3(str);
	}
}
