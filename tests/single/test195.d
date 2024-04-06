module test195;

import config;
import cppconvhelpers;

alias Byte = ubyte;
alias UInt32 = uint;

struct CPpmd8
{
  Byte* Base;
}
// self alias: alias CPpmd8 = CPpmd8;


struct CPpmd_State
{
}
// self alias: alias CPpmd_State = CPpmd_State;

static if (defined!"PPMD_32BIT")
{

  /+ #ifdef PPMD_32BIT +/
    alias CPpmd_State_Ref = CPpmd_State*
  /+ #else
    UInt32
  #endif +/
;
}
static if (!defined!"PPMD_32BIT")
{
alias CPpmd_State_Ref = UInt32;
}

struct CPpmd8_Context_
{
  CPpmd_State_Ref Stats;
}
alias CPpmd8_Context = CPpmd8_Context_;

static if (defined!"PPMD_32BIT")
{
  /+ #define Ppmd8_GetPtr(p3, ptr) (ptr) +/
  /+ #define Ppmd8_GetStats(p3, ctx4) ((ctx4)->Stats) +/
extern(D) alias Ppmd8_GetStats = function string(string p3, string ctx4)
{
    return mixin(interpolateMixin(q{(($(ctx4)).Stats)}));
};
}
static if (!defined!"PPMD_32BIT")
{
  /+ #define Ppmd8_GetPtr(p2, offs) ((void *)((p2)->Base + (offs))) +/
extern(D) alias Ppmd8_GetPtr = function string(string p2, string offs)
{
    return mixin(interpolateMixin(q{(cast(void*)(($(p2)).Base + ($(offs))))}));
};
  /+ #define Ppmd8_GetStats(p2, ctx3) ((CPpmd_State *)Ppmd8_GetPtr((p2), ((ctx3)->Stats))) +/
extern(D) alias Ppmd8_GetStats = function string(string p2, string ctx3)
{
    return mixin(interpolateMixin(q{(cast(CPpmd_State*) mixin(Ppmd8_GetPtr(q{($(p2))}, q{(($(ctx3)).Stats)})))}));
};
}

/+ #define STATS(ctx2) Ppmd8_GetStats(p, ctx2) +/
extern(D) alias STATS = function string(string ctx2)
{
    return mixin(interpolateMixin(q{mixin((defined!"PPMD_32BIT") ? q{
                 mixin(Ppmd8_GetStats(q{p}, q{$(ctx2)}))
             } : q{
                mixin(Ppmd8_GetStats(q{p}, q{$(ctx2)}))
             })}));
};

alias CTX_PTR = CPpmd8_Context*;

void* ShrinkUnits(CPpmd8* p, void* oldPtr, uint oldNU, uint newNU);

void Refresh(CPpmd8* p, CTX_PTR ctx1, uint oldNU)
{
  uint i = 0;
  CPpmd_State* s = cast(CPpmd_State*)ShrinkUnits(p, mixin(STATS(q{ctx1})), oldNU, (i + 2) >> 1);
}

