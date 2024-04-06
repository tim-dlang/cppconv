module testcomments4;

import config;
import cppconvhelpers;

/+ #define f(x) /*comment a1*/ x +/ /*comment a2*/
template f(params...) if (params.length == 1)
{
    enum x = params[0];
    enum f = /*comment a1*/ x; /*comment a2*/
}
/+ #define g(y) /*comment b1*/f/*comment b2*/(/*comment b3*/y/*comment b4*/)/*comment b5*/ + +/ /*comment b6*/

__gshared int z = /*comment c1*/ f!(4)/+ g/*comment c2*/(/*comment c3*/4/*comment c4*/) +/+/*comment c5*/1/*comment c6*/;

