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
    return mixin(interpolateMixin(q{imported!q{testdefines50}.write_impl($(s))}));
};
extern(D) alias write2__1 = function string(string s)
{
    return mixin(interpolateMixin(q{imported!q{testdefines50}.write_impl($(s));}));
};
/+ #define write3(s) write_impl_debug(s, __FILE__, __LINE__) +/
extern(D) alias write3 = function string(string s)
{
    return mixin(interpolateMixin(q{imported!q{testdefines50}.write_impl_debug($(s), __FILE__, __LINE__)}));
};
/+ #define write4(s) write_impl(s); +/
extern(D) alias write4 = function string(string s)
{
    return mixin(interpolateMixin(q{imported!q{testdefines50}.write_impl($(s));}));
};
}
static if (!defined!"DEF")
{
void write(const(char)* s);
void write2(const(char)* s);
void write3(const(char)* s);
void write4(const(char)* s);
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
	static if (!defined!"DEF")
	{
    	write4("test");
	}
	else
	{
    mixin(write4(q{"test"}));
	}
static if (defined!"DEF")
{
}
}
void g(const(char)* str)
{
	mixin((defined!"DEF") ? q{
        	write
    	} : q{
        write
    	})(str);
	static if (!defined!"DEF")
	{
    	write2(str);
	}
	else
	{
    mixin(write2__1(q{str}));
	}
	(mixin((!defined!"DEF") ? q{
        	write3(str)
    	} : q{
        (mixin(write3(q{str})))
    	}));
	static if (!defined!"DEF")
	{
    	write4(str);
	}
	else
	{
    mixin(write4(q{str}));
	}
static if (defined!"DEF")
{
}
}

