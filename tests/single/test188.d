module test188;

import config;
import cppconvhelpers;

struct S
{
	int x;
	int y;
	int version_;
	int init_;
}
// self alias: alias S = S;

void f()
{
	S s = (){
    	S r;
    	
		r.x = 1;
		r.y = 2;
		r.version_ = 3;
		r.init_ = 3;
    	return r;
	}()

	;
	/+ S[0]  +/ auto s2 = mixin(buildStaticArray!(q{S}, q{(){
    	S r;
    	
		r.version_ = 10;
		r.init_ = 11;
		r.x = 12;
		r.y = 13;
    	return r;
	}()

	,
	(){
    	S r;
    	
		r.x = 20;
		r.version_ = 21;
		r.y = 22;
		r.init_ = 23;
    	return r;
	}()

	}));
}

