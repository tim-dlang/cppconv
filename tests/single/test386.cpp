int i1;
const int i2 = 5;

const int *p1 = &i2;
int * const p2 = &i1;
const int * const p3 = &i2;

const int * *p4 = &p1;
int * const * const p5 = &p2;
const int * const * const p6 = &p3;
