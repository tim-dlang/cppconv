module test138;

import config;
import cppconvhelpers;

struct archive;
extern(D) static __gshared /+ ubyte[0]   +/ auto archive__1 = mixin(buildStaticArray!(q{ubyte}, q{cast(ubyte) (1), cast(ubyte) (2), cast(ubyte) (3), cast(ubyte) (4)}));
void f()
{
	ulong   size = (archive__1). sizeof;
}

