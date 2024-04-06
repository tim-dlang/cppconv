module testconflict_cu_f_6;

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
static if (defined!"DEF")
{
__gshared int b;
}
static if (!defined!"DEF")
{
alias b = int;
}
void f()
{
  if ( mixin((defined!"DEF") ? q{
          (b) - 1 != (a) - 1
      } : q{
        cast(b)-1!=cast(a)-1
      }))
  {}
}

