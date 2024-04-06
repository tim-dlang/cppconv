module test113;

import config;
import cppconvhelpers;

struct SHA1_CTX {
}
// self alias: alias SHA1_CTX = SHA1_CTX;

int  SHA1DCFinal(ubyte/+[20]+/* , SHA1_CTX*);

struct git_hash_ctx {
	SHA1_CTX c;
}

struct git_oid {
	ubyte[20]  id;
}

int git_hash_final(git_oid* out_, git_hash_ctx* ctx)
{
	if (SHA1DCFinal(out_.id.ptr, &ctx.c)) {
		return -1;
	}

	return 0;
}

