module test201;

import config;
import cppconvhelpers;

alias Char = ubyte;

extern(D) static __gshared /+ const(char)[0]  +/ auto s1 = staticString!(const(char), "test");
extern(D) static __gshared /+ const(Char)[0]  +/ auto s2 = castStaticArray!( const(Char)[] ) (staticString!(const(Char), "test"));
extern(D) static __gshared /+ const(byte)[0]   +/ auto s3 = castStaticArray!( const(byte)[] ) (staticString!(const(byte), "test"));

