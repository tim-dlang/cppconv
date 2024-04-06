module test118;

import config;
import cppconvhelpers;

/+ #define SIZE_MAX 0xffffffff +/
enum SIZE_MAX = 0xffffffff;

struct git_vector {
	void** contents;
	size_t length;
}
// self alias: alias git_vector = git_vector;

/+ #define git_vector_rforeach(v, iter, elem)	\
	for ((iter) = (v)->length - 1; (iter) < SIZE_MAX && ((elem) = (v)->contents[(iter)], 1); (iter)-- ) +/

struct git_attr_file {
	git_vector rules;			/* vector of <rule*> or <fnmatch*> */
}
// self alias: alias git_attr_file = git_attr_file;

struct git_attr_rule {
}
// self alias: alias git_attr_rule = git_attr_rule;

struct git_attr_path {
}
// self alias: alias git_attr_path = git_attr_path;

int git_attr_rule__match(
	git_attr_rule* rule,
	git_attr_path* path)
{
	return 1;
}

/* loop over rules in file from bottom to top */
/+ #define git_attr_file__foreach_matching_rule(file, path, iter, rule)	\
	git_vector_rforeach(&(file)->rules, (iter), (rule)) \
		if (git_attr_rule__match((rule), (path))) +/

int git_attr_file__lookup_one(
	git_attr_file* file,
	git_attr_path* path)
{
	size_t i;
	git_attr_rule* rule;

	/+ git_attr_file__foreach_matching_rule(file, path, i, rule) +/for(((i))=(&(file).rules).length-1;((i))< SIZE_MAX&&((){(){return ((rule))=cast(git_attr_rule*) ((&(file).rules).contents[((i))]);
}();
return 1;
}());i--)if(git_attr_rule__match((rule),(path))) {


	}

	return 0;
}

