int n[2] = {0, 0};
struct X
{
	int *next;
};
struct S
{
	struct X x;
} s = {{n}}, *state = &s;
int main(void)
{
	return *(state->x.next)++;
}
