/*struct S*/
module testcomments1;

import config;
import cppconvhelpers;

	/+ #define N 2 +/
struct X{float x_f;}
struct Y{float y_f;}
struct S
{
	/*define N*/
	/+ #define N 2 +/
	/*struct X*/
	/+ struct X
	{
		/*member x_f*/
		float x_f;
		/*end of X*/
	}; +/
	/*member x*/
	X x;
	/*struct Y and member y*/
	Y y;
	/*member i*/
	int i;
}

/*function f*/
int f(S* s /*param s*/, int i /*param i*/)
{
	/*return statement*/
	return i;
}
/*eof comment*/

