module testcomments12;

import config;
import cppconvhelpers;

extern(C++, class) struct C
{
public:
	/*comment1*/
	void f(); /*comment2*/
	/*comment3*/
	static if (defined!"DEF")
	{
    	/*comment4*/
    	void g(); /*comment5*/
		/*comment6*/
	}
	/*comment7*/
	void h(); /*comment8*/
	/*comment9*/
}

