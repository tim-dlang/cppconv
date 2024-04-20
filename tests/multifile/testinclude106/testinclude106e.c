#include "testinclude106d.h"

static unsigned char data[16] = {301, 302, 303};

#define DATA2 data[2]

int get_data2(void)
{
    return DATA2;
}

unsigned char get_data_e(int i)
{
    return data[i];
}
