namespace N
{
    template<typename T>
    struct IsAssociativeContainer
    {
        enum { Value = false };
    };
}

#define X(NAME) \
	namespace N \
	{ \
		template<> \
		struct IsAssociativeContainer<NAME> \
		{ \
			enum { Value = true }; \
		}; \
	}

struct A;
struct B;
struct C;

X(A)
X(B)
X(C)

namespace N
{
	/*comment*/
}
