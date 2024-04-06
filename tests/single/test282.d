
module test282;

import config;
import cppconvhelpers;

/+ #define Q_DISABLE_COPY(Class) \
    Class(const Class &) = delete;\
    Class &operator=(const Class &) = delete;

#define Q_DISABLE_MOVE(Class) \
    Class(Class &&) = delete; \
    Class &operator=(Class &&) = delete;

#define Q_DISABLE_COPY_MOVE(Class) \
    Q_DISABLE_COPY(Class) \
    Q_DISABLE_MOVE(Class) +/

extern(C++, class) struct C
{
public:
	@disable this();
	pragma(mangle, defaultConstructorMangling(__traits(identifier, typeof(this))))
	void rawConstructor();
	static typeof(this) create()
	{
    	typeof(this) r = typeof(this).init;
    	r.rawConstructor();
    	return r;
	}

	~this();

private:
	/+ Q_DISABLE_COPY_MOVE(C) +/
@disable this(this);
/+this(ref const(C));+//+ref C operator =(ref const(C));+/}

