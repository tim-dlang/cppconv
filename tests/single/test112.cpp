#ifndef _Restrict_arr_
#  define _Restrict_arr_
#endif

struct regmatch_t
{};

extern int regexec(regmatch_t __pmatch[_Restrict_arr_]);

void f()
{
	regmatch_t pmatch[2];

	regexec(pmatch);
}
