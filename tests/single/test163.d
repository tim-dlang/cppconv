module test163;

import config;
import cppconvhelpers;

struct _TEB;
_TEB*  NtCurrentTeb()
{
    _TEB* teb;
    /+ __asm__(".byte 0x65\n\tmovq (0x30),%0" : "=r" (teb)); +/
    return teb;
}

