module testinclude86;

import config;
import cppconvhelpers;


extern(C++, class) struct RefCount
{

}

struct QArrayData
{
    /+ QtPrivate:: +/RefCount ref_;
}
__gshared QArrayData data;

