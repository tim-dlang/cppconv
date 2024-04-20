module testinclude106e;

import config;
import cppconvhelpers;

extern(D) static __gshared ubyte[16]  data = mixin(buildStaticArray!(q{ubyte}, 16, q{cast(ubyte) (301), cast(ubyte) (302), cast(ubyte) (303)}));

/+ #define DATA2 data[2] +/
enum DATA2 = q{imported!q{testinclude106e}.data[2]};

int get_data2()
{
    return mixin(DATA2);
}

ubyte  get_data_e(int i)
{
    return data[i];
}

