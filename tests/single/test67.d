module test67;

import config;
import cppconvhelpers;

__gshared int i1 = cast(int)4;
__gshared ubyte  c2 = cast(ubyte)3;
__gshared const(char)* s3 = cast(const(char)*)"test";
struct S
{
}
__gshared S* x4 = cast(S*)0;

