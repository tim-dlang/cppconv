static struct _TEB * NtCurrentTeb(void)
{
    struct _TEB *teb;
    __asm__(".byte 0x65\n\tmovq (0x30),%0" : "=r" (teb));
    return teb;
}
