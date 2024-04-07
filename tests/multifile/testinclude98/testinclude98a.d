module testinclude98a;

import config;
import cppconvhelpers;

/+ #define	major_freebsd(x)	((Int32)(((x) & 0x0000ff00) >> 8)) +/
extern(D) alias major_freebsd = function string(string x)
{
    return	mixin(interpolateMixin(q{(cast(imported!q{testinclude98b}.Int32)((($(x)) & 0x0000ff00) >> 8))}));
};

__gshared int i = mixin(major_freebsd(q{0x0101}));

/+ #define D X + X +/
enum D = q{mixin(imported!q{testinclude98b}.X) + mixin(imported!q{testinclude98b}.X)};

void g()
{
    int y = mixin(D);
}

