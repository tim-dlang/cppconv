//const int sizeint = sizeof int;
module test54;

import config;
import cppconvhelpers;

__gshared const(int) sizeint2 = cast(const(int)) (int.sizeof);
__gshared const(int) sizeint3 = cast(const(int)) ( sizeint2. sizeof);
__gshared const(int) sizeint4 = cast(const(int)) ((sizeint2). sizeof);

