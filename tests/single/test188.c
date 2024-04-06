typedef struct S
{
	int x;
	int y;
	int version;
	int init;
} S;

void f()
{
	S s = {
		.x = 1,
		.y = 2,
		.version = 3,
		.init = 3,
	};
	S s2[] = {{
		.version = 10,
		.init = 11,
		.x = 12,
		.y = 13,
	},
	{
		.x = 20,
		.version = 21,
		.y = 22,
		.init = 23,
	}};
}
