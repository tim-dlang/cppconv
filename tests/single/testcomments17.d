module testcomments17;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	struct S
	{
	}
}

/*comment1*/
/*comment2*/__gshared const(C/*comment3*/./*comment4*/S)*/*comment6*/[/*comment8*/3/*comment9*/]/*comment7*//*comment5*/ o/*comment10*/;/*comment11*/

