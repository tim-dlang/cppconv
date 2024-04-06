/*comment1*/
module testcomments14;

import config;
import cppconvhelpers;


/*comment2*/
struct S
{
}

/*comment3*/

/*comment4*/
static if (!defined!"DEF")
{
struct S2;
}


/*comment5*/
static if (defined!"DEF")
{
/*comment6*/
struct S2
{
}
/*comment7*/
}

/*comment8*/

/*comment9*/

