module test288;

import config;
import cppconvhelpers;

/+ #if 0
#elif defined(Q_CLANG_QDOC) +/
static if (defined!"Q_CLANG_QDOC")
{
void f();
}
/+ #endif +/

