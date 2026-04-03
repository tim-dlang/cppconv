void func_impl(int i, const char *file, int line);
#define func(i) func_impl(i, __FILE__, __LINE__)

void main()
{
    func(1);
}
