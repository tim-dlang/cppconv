namespace std
{
  template<typename _Tp, _Tp __v>
    struct integral_constant
    {
      static constexpr _Tp                  value = __v;
      typedef _Tp                           value_type;
      typedef integral_constant<_Tp, __v>   type;
      constexpr operator value_type() const noexcept { return value; }
    };
  template<typename _Tp, _Tp __v>
    constexpr _Tp integral_constant<_Tp, __v>::value;
  typedef integral_constant<bool, true>     true_type;
  typedef integral_constant<bool, false>    false_type;

  template<bool, typename, typename>
    struct conditional;
  template<bool _Cond, typename _Iftrue, typename _Iffalse>
    struct conditional
    { typedef _Iftrue type; };
  template<typename _Iftrue, typename _Iffalse>
    struct conditional<false, _Iftrue, _Iffalse>
    { typedef _Iffalse type; };

  template<typename _Tp>
    struct is_unsigned
    : public true_type
    { };

  template<typename _Tp>
    struct underlying_type
    {
      typedef unsigned   type;
    };
}

template<typename Enum>
class QFlags
{
    typedef typename std::conditional<
            std::is_unsigned<typename std::underlying_type<Enum>::type>::value,
            unsigned int,
            signed int
        >::type Int;
};

template <typename T>
T toIntegral_helper()
{
	using Int32 = typename std::conditional<std::is_unsigned<T>::value, unsigned int, int>::type;
}
