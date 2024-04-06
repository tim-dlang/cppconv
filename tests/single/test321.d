module test321;

import config;
import cppconvhelpers;

extern(C++, "std")
{
      struct integral_constant(_Tp, _Tp __v)
    {
      extern(D) static immutable _Tp                  value = __v;
      alias value_type = _Tp;
      alias type = integral_constant!(_Tp, __v);
      /+auto opCast(T : value_type)() const/+ noexcept+/ { return value; }+/
    }
  alias true_type = integral_constant!(bool, true);
  alias false_type = integral_constant!(bool, false);

      struct conditional(bool _Cond, _Iftrue, _Iffalse)
    { alias type = _Iftrue; }
  /+ template<typename _Iftrue, typename _Iffalse>
    struct conditional<false, _Iftrue, _Iffalse>
    { typedef _Iffalse type; }; +/

      struct is_unsigned(_Tp)

    {
      public true_type base0;
      alias base0 this;
 }

      struct underlying_type(_Tp)
    {
      alias type = uint;
    }
}

extern(C++, class) struct QFlags(Enum)
{
private:
    alias Int = /+ std:: +/
            conditional!(
                /+ std:: +/is_unsigned!(/+ std:: +/underlying_type!(Enum).type).integral_constant.value,
                uint,
                int).type;
}

T toIntegral_helper(T)()
{
	alias Int32 = /+ std:: +/conditional!(/+ std:: +/is_unsigned!(T).integral_constant.value, uint, int).type;
}

