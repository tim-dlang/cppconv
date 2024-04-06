void f(int *data)
{

}
void g()
{
	int data[4];
	f(data);
	int *data2 = data;
	f(data2);
}
