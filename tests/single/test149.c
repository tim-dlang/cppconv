typedef unsigned long size_t;
typedef unsigned long uint32_t;
#define UNICODE_MAX 0x10FFFF
#define UNICODE_R_CHAR 0xFFFD
size_t unicode_to_utf8(char *p, size_t remaining, uint32_t uc)
{
	char *_p = p;

	/* Invalid Unicode char maps to Replacement character */
	if (uc > UNICODE_MAX)
		uc = UNICODE_R_CHAR;
	/* Translate code point to UTF8 */
	if (uc <= 0x7f) {
		if (remaining == 0)
			return (0);
		*p++ = (char)uc;
	} else if (uc <= 0x7ff) {
		if (remaining < 2)
			return (0);
		*p++ = 0xc0 | ((uc >> 6) & 0x1f);
		*p++ = 0x80 | (uc & 0x3f);
	} else if (uc <= 0xffff) {
		if (remaining < 3)
			return (0);
		*p++ = 0xe0 | ((uc >> 12) & 0x0f);
		*p++ = 0x80 | ((uc >> 6) & 0x3f);
		*p++ = 0x80 | (uc & 0x3f);
	} else {
		if (remaining < 4)
			return (0);
		*p++ = 0xf0 | ((uc >> 18) & 0x07);
		*p++ = 0x80 | ((uc >> 12) & 0x3f);
		*p++ = 0x80 | ((uc >> 6) & 0x3f);
		*p++ = 0x80 | (uc & 0x3f);
	}
	return (p - _p);
}
