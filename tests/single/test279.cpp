void f()
{
	int i = 0;
	try
	{
		i = 2;
	}
	catch(...)
	{
		i = 5;
		throw;
	}
}
