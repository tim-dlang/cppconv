
module test234;

import config;
import cppconvhelpers;

extern(C++, "QtPrivate")
{
	struct IsCompatibleCharType(T)
	{
		const(int) value = 1;
	}
}

extern(C++, "std")
{
	struct enable_if(int v, T)
	{
		T type;
	}
}

extern(C++, class) struct QStringView
{
public:
    /+ template <typename Char> +/
    alias if_compatible_char(Char) = /+ std:: +/enable_if!(/+ QtPrivate:: +/IsCompatibleCharType!(Char).value, bool).T;
}

