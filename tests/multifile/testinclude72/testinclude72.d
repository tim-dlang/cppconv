module testinclude72;

import config;
import cppconvhelpers;

ubyte*  f()
{
/+ #ifdef DEF +/
	static if (defined!"DEF")
	{
    	extern(D) static __gshared const(ubyte)[5]  data = [cast(const(ubyte)) (11), cast(const(ubyte)) (12), cast(const(ubyte)) (13), cast(const(ubyte)) (14), cast(const(ubyte)) (15)];
	}
/+ #else +/
static if (!defined!"DEF")
{
    extern(D) static __gshared const(ubyte)[5]  data = [cast(const(ubyte)) (1), cast(const(ubyte)) (2), cast(const(ubyte)) (3), cast(const(ubyte)) (4), cast(const(ubyte)) (5)];
}
/+ #endif +/
	return cast(ubyte*) (data.ptr);
}

