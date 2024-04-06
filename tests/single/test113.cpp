typedef struct {
} SHA1_CTX;

int  SHA1DCFinal(unsigned char[20], SHA1_CTX*);

struct git_hash_ctx {
	SHA1_CTX c;
};

struct git_oid {
	unsigned char id[20];
};

int git_hash_final(git_oid *out, git_hash_ctx *ctx)
{
	if (SHA1DCFinal(out->id, &ctx->c)) {
		return -1;
	}

	return 0;
}
