typedef int Int32;

typedef
   struct {
      Int32    blockSize100k;
   }
   DState;

#define RETURN(rrr)                               \
   { retVal = rrr; goto save_state_and_return; };

#define BZ_HDR_0 0x30
#define BZ_DATA_ERROR_MAGIC  (-5)

Int32 BZ2_decompress(DState* s)
{
    Int32 retVal = 0;
    if (s->blockSize100k < (BZ_HDR_0 + 1) ||
        s->blockSize100k > (BZ_HDR_0 + 9)) RETURN(BZ_DATA_ERROR_MAGIC);

    save_state_and_return:
    return retVal;
}
