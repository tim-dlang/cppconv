module test114;

import config;
import cppconvhelpers;

/+ #define NULL 0 +/
enum NULL = null;

struct transport_definition {
	char* prefix;
}
// self alias: alias transport_definition = transport_definition;

extern(D) static __gshared /+ transport_definition[0]  +/ auto transports = mixin("mixin(buildStaticArray!(q{transport_definition}, q{" ~ q{
        	transport_definition( cast(char*) ("git://".ptr)) ,
        	transport_definition( cast(char*) ("http://".ptr)) ,
        	transport_definition( cast(char*) ("https://".ptr)) ,
        	transport_definition( cast(char*) ("file://".ptr)) ,
    }
    ~ (defined!"GIT_SSH" ? q{
        /+ #ifdef GIT_SSH +/
        	transport_definition( cast(char*) ("ssh://".ptr)) ,
        	transport_definition( cast(char*) ("ssh+git://".ptr)) ,
        	transport_definition( cast(char*) ("git+ssh://".ptr)) ,
    }:"")
    ~ q{
        /+ #endif +/
        	transport_definition( NULL) 
}
 ~ "}))");

