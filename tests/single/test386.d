module test386;

import config;
import cppconvhelpers;

__gshared int i1;
__gshared const(int) i2 = 5;

__gshared const(int)* p1 = &i2;
__gshared /*const*/int *  p2 = &i1;
__gshared const(int * ) p3 = &i2;

__gshared const(int)* * p4 = &p1;
__gshared /*const*//*const*/int *  *  p5 = &p2;
__gshared const(int *  * ) p6 = &p3;

