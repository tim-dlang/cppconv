struct S
{
	int x;
};
struct S data;
struct S data = {5};

int main()
{
	return data.x;
}
