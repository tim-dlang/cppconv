
module test354;

import config;
import cppconvhelpers;

/+ #define BAD_CAST (char *) +/

void g(char* );

void f()
{
    g(cast/+ BAD_CAST +/(char*) "test");
}

