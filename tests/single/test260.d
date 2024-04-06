module test260;

import config;
import cppconvhelpers;

struct QTypeInfo(T)
{
	enum
	{
		isRelocatable = 1
	}
}

struct S
{
	enum E
	{
		X,
		Y
	}
}
	/+ #define CHECK_TYPE(t, relocatable) do { \
		if(QTypeInfo<t>::isRelocatable == relocatable){} \
		} while(0); +/
extern(D) alias CHECK_TYPE = function string(string t, string relocatable)
{
    return mixin(interpolateMixin(q{do {
        		if(QTypeInfo!($(t)).isRelocatable == $(relocatable)){}
        		} while(0);}));
};

void f()
{
	/+ #define CHECK_TYPE(t, relocatable) do { \
		if(QTypeInfo<t>::isRelocatable == relocatable){} \
		} while(0); +/
	mixin(CHECK_TYPE(q{double}, q{1}));
	mixin(CHECK_TYPE(q{S}, q{1}));
	mixin(CHECK_TYPE(q{S*}, q{1}));
	mixin(CHECK_TYPE(q{S.E}, q{1}));
}

