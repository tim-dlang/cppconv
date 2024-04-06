module test165;

import config;
import cppconvhelpers;

alias uint32_t = ulong;

struct mtree_writer {
	uint32_t crc;
}

struct reg_info {
	uint32_t crc;
}

void
sum_final(mtree_writer* mtree, reg_info* reg)
{
	reg.crc = ~mtree.crc;
}

