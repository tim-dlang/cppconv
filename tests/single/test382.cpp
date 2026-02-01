unsigned int array[3] = {1, 2, 3};

unsigned int f()
{
    unsigned int r = 0;
    for (unsigned int x : array)
    {
        r += x;
    }
    return r;
}
