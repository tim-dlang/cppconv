
namespace QtPrivate
{
	template<typename T>
	struct IsCompatibleCharType
	{
		const int value = 1;
	};
}

namespace std
{
	template<int v, typename T>
	struct enable_if
	{
		T type;
	};
}

class QStringView
{
public:
    template <typename Char>
    using if_compatible_char = typename std::enable_if<QtPrivate::IsCompatibleCharType<Char>::value, bool>::type;
};
