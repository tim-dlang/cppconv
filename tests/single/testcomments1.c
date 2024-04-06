/*struct S*/
struct S
{
	/*define N*/
	#define N 2
	/*struct X*/
	struct X
	{
		/*member x_f*/
		float x_f;
		/*end of X*/
	};
	/*member x*/
	struct X x;
	/*struct Y and member y*/
	struct Y
	{
		/*member y_f*/
		float y_f;
		/*end of Y*/
	} y;
	/*member i*/
	int i;
};

/*function f*/
int f(struct S *s /*param s*/, int i /*param i*/)
{
	/*return statement*/
	return i;
}
/*eof comment*/
