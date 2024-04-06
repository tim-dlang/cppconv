struct git_revwalk {
	unsigned walking:1,
		first_parent: 1,
		did_hide: 1,
		did_push: 1;

};

void git_revwalk_reset(git_revwalk *walk)
{
	walk->first_parent = 0;
	walk->walking = 0;
	walk->did_push = walk->did_hide = 0;
}
