typedef unsigned long long size_t;
struct trie_node
{};
struct git_oid_shorten {
	trie_node *nodes;
	size_t node_count, size;
	int min_length, full;
};
