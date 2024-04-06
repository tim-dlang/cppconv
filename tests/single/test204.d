module test204;

import config;
import cppconvhelpers;

union pthread_attr_t
{
  char[10] __size;
  long  __align;
}
static if (!defined!"__have_pthread_attr_t")
{
alias pthread_attr_t__1 = pthread_attr_t;
/+ # define __have_pthread_attr_t 1 +/
}

