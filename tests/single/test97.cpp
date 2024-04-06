int f(int i)
{
	int r = 1;
	switch(i)
	{
		case 1:
		r *= 3;
		case 2:
		r *= 4;
		case 3:
		r *= 5;
		default:
		r *= 6;
	}
	return r;
}
