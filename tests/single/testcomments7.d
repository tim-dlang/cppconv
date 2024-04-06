module testcomments7;

import config;
import cppconvhelpers;

/+ #define f(a, b) /*commenta1*/a +//*commenta2*/
extern(D) alias f = function string(string a, string b)
{
    return /*commenta1*/ mixin(interpolateMixin(q{$(a)}));/*commenta2*/
};
/+ #define g /*commentb1*/f +//*commentb2*/
enum g = /*commentb1*/ mixin(f(q{1},q{}));/*commentb2*/
__gshared int i = /*commentc1*/ g/*commentc2*//+ (/*commentc3*/1/*commentc4*/,/*commentc5*/2/*commentc6*/) +//*commentc7*/;/*commentc8*/

// tags: higher-order-macro

