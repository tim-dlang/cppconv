module testinclude99a;

import config;
import cppconvhelpers;

/+ #define	M(x) x + x +/
extern(D) alias M = function string(string x)
{
    return mixin(interpolateMixin(q{$(x) + $(x)}));
};

void g()
{
    import testinclude99b;

    int z = mixin(M(q{mixin(X)}));
}

