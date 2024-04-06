module test117;

import config;
import cppconvhelpers;

struct S;
// self alias: alias S = S;
void* git_pool_malloc(uint  size);

S** f(uint  count)
{
	return cast(S**) (git_pool_malloc ( cast(uint) (count *  (S*).sizeof) ));
}

