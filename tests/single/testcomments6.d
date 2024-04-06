module testcomments6;

import config;
import cppconvhelpers;

/+ #define f(a, b, c) 1 +/
extern(D) alias f = function string(string a, string b, string c)
{
    return mixin(interpolateMixin(q{1}));
};
__gshared int i1 = /*commenta1*/ mixin(f/*commenta2*/(q{/*commenta3*/1/*commenta4*/},q{/*commenta5*/2/*commenta6*/},q{/*commenta7*/3/*commenta8*/}))/*commenta9*/;

/+ #define X /*commentb1*/f/*commentb2*/(/*commentb3*/4/*commentb4*/,/*commentb5*/5/*commentb6*/,/*commentb7*/6/*commentb8*/) +//*commentb9*/
enum X = /*commentb1*/ mixin(f/*commentb2*/(q{/*commentb3*/4/*commentb4*/},q{/*commentb5*/5/*commentb6*/},q{/*commentb7*/6/*commentb8*/}));/*commentb9*/
__gshared int i2 = X;

/+ #define g(b) /*commentc1*/f/*commentc2*/(/*commentc3*/7/*commentc4*/,/*commentc5*/b/*commentc6*/,/*commentc7*/9/*commentc8*/) +//*commentc9*/
__gshared int i3 = /*commentd1*/ mixin(f(q{/*commentc3*/7/*commentc4*/},q{/*commentc5*/b/*commentc6*/},q{/*commentc7*/9/*commentc8*/}))/+ g/*commentd2*/(/*commentd3*/8/*commentd4*/) +//*commentd5*/;

/+ #define h(b) /*commente1*/g/*commente2*/(/*commente3*/f/*commente4*/(/*commente5*/,/*commente6*/,/*commente7*/)/*commente8*/) +//*commente9*/
extern(D) alias h = function string(string b)
{
    return /*commente1*/ mixin(interpolateMixin(q{ mixin(f(q{/*commentc3*/7/*commentc4*/},q{/*commentc5*/b/*commentc6*/},q{/*commentc7*/9/*commentc8*/}))/+ g/*commente2*/(/*commente3*/f/*commente4*/(/*commente5*/,/*commente6*/,/*commente7*/)/*commente8*/) +/}));/*commente9*/
};
__gshared int i4 = /*commentf1*/ mixin(h/*commentf2*/(q{/*commentf3*/10/*commentf4*/}))/*commentf5*/;/*commentf6*/

