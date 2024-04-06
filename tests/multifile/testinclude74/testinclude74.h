#define str(s) #s

#define test str(test test)

const char *test1 = test;
const char *test2 = str(test in header);
