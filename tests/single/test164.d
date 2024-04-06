module test164;

import config;
import cppconvhelpers;

static if (!defined!"__COMPAR_FN_T")
{
/+ # define __COMPAR_FN_T +/
alias __compar_fn_t = int function( const(void)* , const(void)* );
}

void qsort (mixin((!defined!"__COMPAR_FN_T") ? q{__compar_fn_t } : q{AliasSeq!()}) __compar);

int _compare_path_table(const(void)* v1, const(void)* v2);

void f()
{
	qsort(cast(__compar_fn_t)&_compare_path_table);
	qsort(&_compare_path_table);
}

