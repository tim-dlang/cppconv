module test60;

import config;
import cppconvhelpers;

struct trie_node
{}
struct git_oid_shorten {
	trie_node* nodes;
	size_t node_count; size_t size;
	int min_length; int full;
}

