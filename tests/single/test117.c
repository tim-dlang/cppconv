typedef struct S S;
void* git_pool_malloc(unsigned int size);

S** f(unsigned int count)
{
	return git_pool_malloc ( count * sizeof (S*) );
}
