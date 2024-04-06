// FogThesis.pdf 152
// FogThesis.pdf 367

#ifdef DEF
typedef int Y;
#else
typedef int X;
#endif

struct
#ifdef DEF
X
#else
Z
#endif
{
	X(Y);
};
