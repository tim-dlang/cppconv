module testconflict_cu_f_2;

import config;
import cppconvhelpers;

static if (defined!"DEF")
{
__gshared int a;
}
static if (!defined!"DEF")
{
alias a = int;
}
void f()
{
  if ( mixin((defined!"DEF") ? q{
          2 != (a) -1
      } : q{
        2!=cast(a)-1
      }))
  {}
}

