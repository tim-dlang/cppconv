module test158;

import config;
import cppconvhelpers;

int process_head_file()
{
	enum COMP_INFO_FLAGS {
		SOLID = 0x0040,
	}/+ ; +/
	return COMP_INFO_FLAGS.SOLID;
}

int process_head_main()
{
	enum MAIN_FLAGS {
		VOLUME = 0x0001,         /* multi-volume archive */
		VOLUME_NUMBER = 0x0002,  /* volume number, first vol doesn't
					  * have it */
		SOLID = 0x0004,          /* solid archive */
		PROTECT = 0x0008,        /* contains Recovery info */
		LOCK = 0x0010,           /* readonly flag, not used */
	}/+ ; +/
	return MAIN_FLAGS.SOLID;
}

