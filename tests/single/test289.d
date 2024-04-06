module test289;

import config;
import cppconvhelpers;

extern(C++, "N")
{
    struct IsAssociativeContainer(T)
    {
        enum { Value = false }
    }
}

/+ #define X(NAME) \
	namespace N \
	{ \
		template<> \
		struct IsAssociativeContainer<NAME> \
		{ \
			enum { Value = true }; \
		}; \
	} +/

struct A;
struct B;
struct C;


/+ X(A)
X(B)
X(C)
namespace N
{
	/*comment*/
} +/

