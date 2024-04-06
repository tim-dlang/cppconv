module test183b;

import config;
import cppconvhelpers;

/+ #       define U_ICU_ENTRY_POINT_RENAME(x)    x +/
extern(D) alias U_ICU_ENTRY_POINT_RENAME = function string(string x)
{
    return    mixin(interpolateMixin(q{$(x)}));
};

/+ #define UCNV_FROM_U_CALLBACK_STOP U_ICU_ENTRY_POINT_RENAME(UCNV_FROM_U_CALLBACK_STOP) +/

void UCNV_FROM_U_CALLBACK_STOP/+ UCNV_FROM_U_CALLBACK_STOP +/();

void* f()
{
	return & mixin(U_ICU_ENTRY_POINT_RENAME(q{UCNV_FROM_U_CALLBACK_STOP}))/+ UCNV_FROM_U_CALLBACK_STOP +/;
}

