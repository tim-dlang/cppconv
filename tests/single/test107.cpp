void f(int data[]);
void g(int data[5]);

struct git_oid;
void h(const git_oid *parents[]);

int main()
{
	int data[10];
	f(data);
	g(data);
	const git_oid *parents[10];
	h(parents);
	return 0;
}
