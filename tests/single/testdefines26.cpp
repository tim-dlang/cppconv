#define __STRING(x)	#x
#define __STRING2(x)	__STRING(x)
#define __STRING3(x)	__STRING(x x)
const char *s1 = __STRING(test);
const char *s2 = __STRING2(test2);
const char *s3 = __STRING3(test3);
#define TEST2 test4
const char *s4 = __STRING(TEST4);
const char *s4b = __STRING(TEST4 x);
