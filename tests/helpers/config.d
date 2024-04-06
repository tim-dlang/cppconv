module config;

template defined(string name)
{
    //enum defined = __traits(hasMember, config, name);
    // For tests:
    enum defined = versionIsSet!name;
}

template __has_include(string name)
{
    enum __has_include = false;
}

template configValue(string name)
{
    static if(defined!name)
        mixin("enum configValue = " ~ name ~ ";");
    else
        enum configValue = 0;
}

template versionIsSet(string name)
{
    mixin((){
        string r;
        r ~= "version(" ~ name ~ ")\n";
        r ~= "enum versionIsSet = true;\n";
        r ~= "else\n";
        r ~= "enum versionIsSet = false;\n";
        return r;
        }());
}
