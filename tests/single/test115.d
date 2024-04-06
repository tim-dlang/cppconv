module test115;

import config;
import cppconvhelpers;

int printf (const(char)*/+ __restrict +/  __format, ...);

/* This test checks, that the correct calling convention is used for
 * the function pointer. If the function is extern(C) and the pointer
 * extern(D), then ther arguments are swapped.
 * The problem appeared in git_diff__paired_foreach in libgit2 diff_generate.c.*/

int cmp(int a, int b)
{
	printf("cmp %d %d\n", a, b);
	return a-b;
}

int f(int a, int b)
{
	int function(int, int) cb = &cmp;
	return cb(a, b);
}

int main()
{
	printf("result: %d\n", f(1, 2));
	return 0;
}

