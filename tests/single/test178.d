module test178;

import config;
import cppconvhelpers;


alias xmlMallocFunc = void* function(size_t size);

void* xmlMallocLoc (size_t size, const(char)* file, int line);

/+ #ifdef DEBUG_MEMORY_LOCATION
#define xmlMalloc(size) xmlMallocLoc((size), __FILE__, __LINE__)
#endif /* DEBUG_MEMORY_LOCATION */

#undef	xmlMalloc +/

static if (defined!"LIBXML_THREAD_ALLOC_ENABLED")
{
static if (defined!"LIBXML_THREAD_ENABLED")
{
xmlMallocFunc* __xmlMalloc();
/+ #define xmlMalloc \
(*(__xmlMalloc())) +/
enum xmlMalloc =
q{    (*(imported!q{test178}.__xmlMalloc()))};
}
static if (!defined!"LIBXML_THREAD_ENABLED")
{
__gshared xmlMallocFunc xmlMalloc;
}
}
static if (!defined!"LIBXML_THREAD_ALLOC_ENABLED")
{
__gshared xmlMallocFunc xmlMalloc;
}

struct S1
{
	int i;
}

void f1()
{
	S1* x;
	x = cast(S1*) mixin(((defined!"LIBXML_THREAD_ALLOC_ENABLED" && defined!"LIBXML_THREAD_ENABLED")) ? q{
        	mixin(xmlMalloc)
    	} : q{
        xmlMalloc
    	})(S1.sizeof);
}

struct S2
{
	int i;
}

void f2()
{
	S2* x;
	x = cast(S2*) ( mixin(((defined!"LIBXML_THREAD_ALLOC_ENABLED" && defined!"LIBXML_THREAD_ENABLED")) ? q{
        	mixin(xmlMalloc)
    	} : q{
        xmlMalloc
    	})(S2.sizeof));
}

