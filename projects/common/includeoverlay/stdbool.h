#ifndef _STDBOOL_H
#define _STDBOOL_H

#ifndef __cplusplus

typedef _Bool bool;
#define true	1
#define false	0

#else /* __cplusplus */

/* Supporting _Bool in C++ is a GCC extension.  */
//#define _Bool	bool

#endif /* __cplusplus */

/* Signal that all the definitions are present.  */
#define __bool_true_false_are_defined	1

#endif	/* stdbool.h */
