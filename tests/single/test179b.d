module test179b;

import config;
import cppconvhelpers;

/+ #define U_ICU_VERSION_SUFFIX _67

#define U_DEF_ICU_ENTRY_POINT_RENAME(x,y) x ## y
#define U_DEF2_ICU_ENTRY_POINT_RENAME(x,y) U_DEF_ICU_ENTRY_POINT_RENAME(x,y)
#define U_ICU_ENTRY_POINT_RENAME(x)    U_DEF2_ICU_ENTRY_POINT_RENAME(x,U_ICU_VERSION_SUFFIX) +/

/+ #define ucnv_convertEx U_ICU_ENTRY_POINT_RENAME(ucnv_convertEx) +/
alias ucnv_convertEx = /+ U_ICU_ENTRY_POINT_RENAME(ucnv_convertEx) +/ucnv_convertEx_67;

void ucnv_convertEx_67/+ ucnv_convertEx +/();

void f()
{
	ucnv_convertEx();
}

