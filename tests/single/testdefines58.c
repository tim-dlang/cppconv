#define X a
#define Y b
#define XY(x) x * 5
#define Z X ## Y (2)
int i1 = Z;
