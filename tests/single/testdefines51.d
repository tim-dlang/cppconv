module testdefines51;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
void write_impl(const(char)* s);
/+ #define write write_impl +/
alias write = write_impl;
}
static if (!defined!"DEF")
{
void write(const(char)* s);
}

struct S
{
	static if (defined!"DEF")
	{
	void function(const(char)* s) write_impl;
	}
static if (!defined!"DEF")
{
void function(const(char)* s) write;
}
}

void f1(S* x)
{
	mixin(q{x.
}
~ (defined!"DEF" ? q{
/+ write +/write_impl
}:"")
~ (!defined!"DEF" ? q{
write
}:"")
) = mixin((defined!"DEF") ? q{
        & write
    } : q{
        &write
    });
}

void f2(S* x, const(char)* str)
{
	mixin(q{x.
}
~ (defined!"DEF" ? q{
/+ write +/write_impl
}:"")
~ (!defined!"DEF" ? q{
write
}:"")
)(str);
}

