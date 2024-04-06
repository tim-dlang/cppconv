
module test296;

import config;
import cppconvhelpers;

/+ #define Q_DISABLE_COPY(Class) \
    Class(const Class &) = delete;\
    Class &operator=(const Class &) = delete; +/

class C
{
public:
	this()
	{
	}
	/+ virtual +/~this()
	{
	}

private:
	/+ Q_DISABLE_COPY(C) +/
}

