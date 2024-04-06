typedef unsigned char Byte;
typedef unsigned int UInt32;

typedef struct
{
  Byte *Base;
} CPpmd8;


typedef struct
{
} CPpmd_State;

typedef
  #ifdef PPMD_32BIT
    CPpmd_State *
  #else
    UInt32
  #endif
  CPpmd_State_Ref;

typedef struct CPpmd8_Context_
{
  CPpmd_State_Ref Stats;
} CPpmd8_Context;

#ifdef PPMD_32BIT
  #define Ppmd8_GetPtr(p3, ptr) (ptr)
  #define Ppmd8_GetStats(p3, ctx4) ((ctx4)->Stats)
#else
  #define Ppmd8_GetPtr(p2, offs) ((void *)((p2)->Base + (offs)))
  #define Ppmd8_GetStats(p2, ctx3) ((CPpmd_State *)Ppmd8_GetPtr((p2), ((ctx3)->Stats)))
#endif

#define STATS(ctx2) Ppmd8_GetStats(p, ctx2)

typedef CPpmd8_Context * CTX_PTR;

void *ShrinkUnits(CPpmd8 *p, void *oldPtr, unsigned oldNU, unsigned newNU);

static void Refresh(CPpmd8 *p, CTX_PTR ctx1, unsigned oldNU)
{
  unsigned i = 0;
  CPpmd_State *s = (CPpmd_State *)ShrinkUnits(p, STATS(ctx1), oldNU, (i + 2) >> 1);
}
