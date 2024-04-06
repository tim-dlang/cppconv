
#define Q_DISABLE_COPY(Class) \
    Class(const Class &) = delete;\
    Class &operator=(const Class &) = delete;

class C
{
public:
	C()
	{
	}
	virtual ~C()
	{
	}

private:
	Q_DISABLE_COPY(C)
};
