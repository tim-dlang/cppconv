typedef unsigned long uint32_t;

struct mtree_writer {
	uint32_t crc;
};

struct reg_info {
	uint32_t crc;
};

static void
sum_final(struct mtree_writer *mtree, struct reg_info *reg)
{
	reg->crc = ~mtree->crc;
}
