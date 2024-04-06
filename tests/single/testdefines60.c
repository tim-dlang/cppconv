#define CONCAT2(a, b) a ## b
#define CONCAT(a, b) CONCAT2(a, b)

#define A a
#define B 2 * A
#define C 4 * B

const int ax = 100;

int i = CONCAT(C, x);
