
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.configreader;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.json;
import std.path;
import std.regex;

enum TristateMatch
{
    dontCare,
    matchFalse,
    matchTrue,
}

struct ConfigRegex
{
    string pattern;
    Regex!char regex;
    bool empty = true;
    bool isSimple;
    bool allowPrefix;

    this(string pattern, const(char)[] flags = [], bool allowPrefix = false)
    {
        empty = false;
        this.pattern = pattern;
        this.allowPrefix = allowPrefix;

        isSimple = true;
        foreach (dchar c; pattern)
        {
            if (!c.inCharSet!"a-zA-Z0-9_")
                isSimple = false;
        }
        if (flags)
            isSimple = false;

        if (!isSimple)
            this.regex = std.regex.regex("^(?:" ~ pattern ~ ")" ~ (allowPrefix ? "" : "$"), flags);
    }

    auto namedCaptures()
    {
        return regex.namedCaptures;
    }

    bool match(string s, ref Captures!string captures, ref string post) const
    {
        if (isSimple)
        {
            if (allowPrefix)
            {
                if (s.startsWith(pattern))
                {
                    post = s[pattern.length .. $];
                    return true;
                }
                else
                    return false;
            }
            return s == pattern;
        }
        else if (!regex.empty)
        {
            captures = matchFirst(s, regex);
            if (!captures.empty)
            {
                post = captures.post;
                return true;
            }
            else
                return false;
        }
        else
            return false;
    }

    bool match(string s, ref Captures!string captures) const
    {
        string post;
        return match(s, captures, post);
    }

    bool match(string s, ref string post) const
    {
        Captures!string captures;
        return match(s, captures, post);
    }

    bool match(string s) const
    {
        Captures!string captures;
        string post;
        return match(s, captures, post);
    }
}

struct ConfigRegexMultiline
{
    ConfigRegex regex;
    alias regex this;

    this(string pattern)
    {
        regex = ConfigRegex(pattern, "s", true);
    }
}

void readConfig(T)(ref T config, const JSONValue json)
{
    static if (is(T == ConfigRegex))
    {
        if (json.type() == JSONType.array)
        {
            string combinedRegex = "";
            foreach (i, c; json.array)
            {
                enforce(c.type() == JSONType.string);
                if (i)
                    combinedRegex ~= "|";
                combinedRegex ~= c.str();
            }
            config = ConfigRegex(combinedRegex);
        }
        else
        {
            enforce(json.type() == JSONType.string);
            config = ConfigRegex(json.str());
        }
    }
    else static if (is(T == ConfigRegexMultiline))
    {
        if (json.type() == JSONType.array)
        {
            string combinedRegex = "";
            foreach (i, c; json.array)
            {
                if (c.type() == JSONType.object)
                {
                    combinedRegex ~= c["regex"].str();
                }
                else
                {
                    enforce(c.type() == JSONType.string);
                    combinedRegex ~= text(std.regex.escaper(c.str()));
                    if (i + 1 < json.array.length)
                        combinedRegex ~= "\n";
                }
            }
            config = ConfigRegexMultiline(combinedRegex);
        }
        else
        {
            enforce(json.type() == JSONType.string);
            config = ConfigRegexMultiline(json.str());
        }
    }
    else static if (is(T == TristateMatch))
    {
        enforce(json.type() == JSONType.true_ || json.type() == JSONType.false_);
        config = json.type() == JSONType.true_ ? TristateMatch.matchTrue : TristateMatch.matchFalse;
    }
    else static if (is(T == struct))
    {
        static if (__traits(hasMember, T, "fromStr"))
        {
            if (json.type() == JSONType.string)
            {
                config = T.fromStr(json.str());
                return;
            }
        }
        enforce(json.type() == JSONType.object);
        foreach (name, child; json.objectNoRef)
        {
            bool found;
            static foreach (member; T.tupleof)
            {{
                enum memberName = __traits(identifier, member);
                static assert(memberName != "include", "Config member include is reserved");
                string member2 = memberName;
                if (member2[$ - 1] == '_')
                    member2 = member2[0 .. $ - 1];
                if (name == member2)
                {
                    found = true;
                    readConfig(__traits(getMember, config, memberName), child);
                }
            }}
            if (!found)
            {
                enforce(false, "Unknown config entry " ~ name);
            }
        }
    }
    else static if (is(T == enum))
    {
        enforce(json.type() == JSONType.string);
        string value = json.str();
        foreach (member; __traits(allMembers, T))
        {
            string member2 = member;
            if (member2[$ - 1] == '_')
                member2 = member2[0 .. $ - 1];
            if (value == member2)
            {
                config = __traits(getMember, T, member);
                return;
            }
        }
    }
    else static if (is(T == string))
    {
        enforce(json.type() == JSONType.string);
        config = json.str();
    }
    else static if (is(T == bool))
    {
        enforce(json.type() == JSONType.true_ || json.type() == JSONType.false_);
        config = json.type() == JSONType.true_;
    }
    else static if (is(T == ulong) || is(T == uint) || is(T == ushort) || is(T == ubyte))
    {
        if (json.type() == JSONType.integer)
        {
            config = json.integer();
        }
        else
        {
            enforce(json.type() == JSONType.uinteger);
            config = json.uinteger();
        }
    }
    else static if (is(T == long) || is(T == int) || is(T == short) || is(T == byte))
    {
        enforce(json.type() == JSONType.integer);
        config = json.integer();
    }
    else static if (is(T == C[], C))
    {
        enforce(json.type() == JSONType.array);
        foreach (c; json.array)
        {
            C child;
            readConfig(child, c);
            config ~= child;
        }
    }
    else static if (is(T == C[string], C))
    {
        enforce(json.type() == JSONType.object);
        foreach (name, child; json.objectNoRef)
        {
            if (name !in config)
                config[name] = C.init;
            readConfig(config[name], child);
        }
    }
    else
    {
        static assert(false, T.stringof);
    }
}

string removeComments(string input)
{
    Appender!string app;
    bool inComment;
    bool afterEscape;
    while (input.length)
    {
        if (input[0] == '\"')
        {
            size_t i = 1;
            while (i < input.length)
            {
                i++;
                if (input[i - 1] == '\\' && i < input.length)
                    i++;
                else if (input[i - 1] == '\"')
                    break;
            }
            app.put(input[0 .. i]);
            input = input[i .. $];
        }
        else if (input.startsWith("//"))
        {
            size_t i = 2;
            while (i < input.length && input[i] != '\n')
            {
                i++;
            }
            foreach (j; 0 .. i)
                app.put(' ');
            input = input[i .. $];
        }
        else if (input.startsWith("/*"))
        {
            size_t i = 2;
            while (i < input.length)
            {
                if (input[i .. $].startsWith("*/"))
                {
                    i += 2;
                    break;
                }
                i++;
            }
            foreach (j; 0 .. i)
                app.put(input[j] == '\n' ? '\n' : ' ');
            input = input[i .. $];
        }
        else
        {
            app.put(input[0]);
            input = input[1 .. $];
        }
    }
    return app.data;
}

void readConfig(T)(ref T config, string filename)
{
    bool[string] done;
    void readConfigFile(string filename)
    {
        if (filename in done)
            return;
        done[filename] = true;
        string input = readText(filename);
        input = removeComments(input);
        JSONValue json = parseJSON(input);
        auto obj = json.objectNoRef;
        if ("include" in obj)
        {
            if (obj["include"].type() == JSONType.array)
            {
                foreach (c; obj["include"].array())
                {
                    string filename2 = c.str;
                    filename2 = absolutePath(filename2, dirName(filename));
                    readConfigFile(filename2);
                }
            }
            else
            {
                string filename2 = obj["include"].str;
                filename2 = absolutePath(filename2, dirName(filename));
                readConfigFile(filename2);
            }
            obj.remove("include");
        }
        readConfig(config, json);
    }

    readConfigFile(absolutePath(filename));
}
