module test4;

import config;
import cppconvhelpers;

void f(
/+ #ifdef DEF +/
mixin((defined!"DEF") ? q{int } : q{AliasSeq!()}) i
/+ #endif +/
);

