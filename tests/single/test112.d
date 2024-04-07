module test112;

import config;
import cppconvhelpers;

/+ #ifndef _Restrict_arr_
#  define _Restrict_arr_
#endif +/

struct regmatch_t
{}

int regexec(mixin((defined!"_Restrict_arr_") ? q{regmatch_t/+[_Restrict_arr_]+/* } : q{AliasSeq!()}) __pmatch, mixin((!defined!"_Restrict_arr_") ? q{regmatch_t/+[0]+/*} : q{AliasSeq!()}) __pmatch);

void f()
{
	regmatch_t[2] pmatch;

	regexec(pmatch.ptr);
}

