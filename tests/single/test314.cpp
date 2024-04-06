class C
{
public:
    char data[10];
    inline char &operator[](int j) { return data[j]; }
    char &front()
    {
		return operator[](0);
	}
};
