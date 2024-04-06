typedef unsigned size_t;
#define SIZE_MAX 0xffffffff

typedef struct git_vector {
	void **contents;
	size_t length;
} git_vector;

#define git_vector_rforeach(v, iter, elem)	\
	for ((iter) = (v)->length - 1; (iter) < SIZE_MAX && ((elem) = (v)->contents[(iter)], 1); (iter)-- )

typedef struct {
	git_vector rules;			/* vector of <rule*> or <fnmatch*> */
} git_attr_file;

typedef struct {
} git_attr_rule;

typedef struct {
} git_attr_path;

int git_attr_rule__match(
	git_attr_rule *rule,
	git_attr_path *path)
{
	return 1;
}

/* loop over rules in file from bottom to top */
#define git_attr_file__foreach_matching_rule(file, path, iter, rule)	\
	git_vector_rforeach(&(file)->rules, (iter), (rule)) \
		if (git_attr_rule__match((rule), (path)))

int git_attr_file__lookup_one(
	git_attr_file *file,
	git_attr_path *path)
{
	size_t i;
	git_attr_rule *rule;

	git_attr_file__foreach_matching_rule(file, path, i, rule) {


	}

	return 0;
}
