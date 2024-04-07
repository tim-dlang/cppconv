module testcomments3;

import config;
import cppconvhelpers;

int g(int, int);

/+ #define f1(x,y) /*comment a1*/g/*comment a2*/(/*comment a3*/x/*comment a4*/,/*comment a5*/y/*comment a6*/) +//*comment a7*/
extern(D) alias f1 = function string(string x, string y)
{
    return /*comment a1*/ mixin(interpolateMixin(q{imported!q{testcomments3}.g/*comment a2*/(/*comment a3*/$(x)/*comment a4*/,/*comment a5*/$(y)/*comment a6*/)}));/*comment a7*/
};
/+ #define f2(x,y) /*comment b1*/f1/*comment b2*/(/*comment b3*/x/*comment b4*/,/*comment b5*/y/*comment b6*/) +//*comment b7*/
extern(D) alias f2 = function string(string x, string y)
{
    return /*comment b1*/ mixin(interpolateMixin(q{ mixin(imported!q{testcomments3}.f1/*comment b2*/(/*comment b3*/q{$(x)}/*comment b4*/,/*comment b5*/q{$(y)}/*comment b6*/))}));/*comment b7*/
};

/+ #define X1 /*comment c1*/42 +//*comment c2*/
enum X1 = /*comment c1*/42;/*comment c2*/
/+ #define X2 /*comment d1*/f1/*comment d2*/(/*comment d3*/2/*comment d4*/,/*comment d5*/3/*comment d6*/) +//*comment d7*/
enum X2 = /*comment d1*/q{ mixin(imported!q{testcomments3}.f1/*comment d2*/(/*comment d3*/q{2}/*comment d4*/,/*comment d5*/q{3}/*comment d6*/))};/*comment d7*/
/+ #define X3 /*comment e1*/f2/*comment e2*/(/*comment e3*/4/*comment e4*/,/*comment e5*/5/*comment e6*/) +//*comment e7*/
enum X3 = /*comment e1*/q{ mixin(imported!q{testcomments3}.f2/*comment e2*/(/*comment e3*/q{4}/*comment e4*/,/*comment e5*/q{5}/*comment e6*/))};/*comment e7*/

int main()
{
	int i1 = /*comment f1*/ mixin(f1/*comment f2*/(/*comment f3*/q{6}/*comment f4*/,/*comment f5*/q{7}/*comment f6*/))/*comment f7*/;/*comment f8*/
	int i2 = /*comment g1*/ mixin(f2/*comment g2*/(/*comment g3*/q{8}/*comment g4*/,/*comment g5*/q{9}/*comment g6*/))/*comment g7*/;/*comment g8*/
	int i3 = /*comment h1*/ X1/*comment h2*/;
	int i4 = /*comment i1*/ mixin(X2)/*comment i2*/;
	int i5 = /*comment j1*/ mixin(X3)/*comment j2*/;

	return 0;
}

