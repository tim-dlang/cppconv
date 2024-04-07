module test98;

import config;
import cppconvhelpers;

/+ #define	__S_IFMT	0170000 +/
enum __S_IFMT =	octal!170000;
/+ #define	__S_IFLNK	0120000 +/
enum __S_IFLNK =	octal!120000;
/+ #define	__S_ISTYPE(mode, mask)	(((mode) & __S_IFMT) == (mask)) +/
extern(D) alias __S_ISTYPE = function string(string mode, string mask)
{
    return	mixin(interpolateMixin(q{((($(mode)) & imported!q{test98}.__S_IFMT) == ($(mask)))}));
};
/+ # define S_ISLNK(mode)	 __S_ISTYPE((mode), __S_IFLNK) +/
extern(D) alias S_ISLNK = function string(string mode)
{
    return	 mixin(interpolateMixin(q{mixin(imported!q{test98}.__S_ISTYPE(q{($(mode))}, q{imported!q{test98}.__S_IFLNK}))}));
};
void f(int mode){
	if (mixin(S_ISLNK(q{mode}))){}
}

