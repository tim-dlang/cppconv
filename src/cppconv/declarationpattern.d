
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.declarationpattern;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.locationstack;
import dparsergen.core.utils;
import std.algorithm;
import std.conv;
import std.path;
import std.range;
import std.regex;
import std.stdio;
import std.uni;
import std.utf;

struct DeclarationPattern
{
    ConfigRegex filename;
    ConfigRegex name;
    size_t[] lines;
    TristateMatch isTemplate;
    TristateMatch inMacro;

    bool used;
    bool redundant;

    static DeclarationPattern fromStr(string s)
    {
        DeclarationPattern r;
        r.name = ConfigRegex(s);
        return r;
    }
}

struct DeclarationMatch
{
    Captures!string filenameMatch;
    Captures!string nameMatch;
}

bool isDeclarationMatch(ref DeclarationPattern pattern, ref DeclarationMatch match,
        string filename, size_t startLine, bool inMacro, string name, DeclarationFlags flags)
{
    if (!pattern.filename.empty)
    {
        if (!pattern.filename.match(filename, match.filenameMatch))
            return false;
    }
    if (pattern.lines.length)
    {
        bool inRange;
        for (size_t i = 0; i < pattern.lines.length; i += 2)
        {
            if (startLine < pattern.lines[i] - 1)
                continue;
            if (i + 1 < pattern.lines.length && startLine >= pattern.lines[i + 1] - 1)
                continue;
            inRange = true;
            break;
        }
        if (!inRange)
            return false;
    }
    if (name.empty && !pattern.name.empty)
        return false;
    if (!pattern.name.empty)
    {
        if (!pattern.name.match(name, match.nameMatch))
            return false;
    }
    if (pattern.isTemplate != TristateMatch.dontCare)
        if (((flags & DeclarationFlags.template_) != 0) != (pattern.isTemplate == TristateMatch.matchTrue))
            return false;
    if (pattern.inMacro != TristateMatch.dontCare)
        if (inMacro != (pattern.inMacro == TristateMatch.matchTrue))
            return false;
    pattern.used = true;
    return true;
}

bool isDeclarationMatch(ref DeclarationPattern pattern, ref DeclarationMatch match, Declaration d)
{
    bool inMacro;
    LocationRangeX location = d.location;
    if (location.context is null || location.context.contextDepth < 1)
        return false;
    return isDeclarationMatch(pattern, match, location.context.filename,
            location.start.line, inMacro, d.name, d.flags);
}

string translateResult(ref DeclarationPattern pattern, ref DeclarationMatch match, string s)
{
    string r;
    int caseChange;
    void append(string s)
    {
        if (caseChange < 0)
            r ~= s.toLower;
        else if (caseChange > 0)
            r ~= s.toUpper;
        else
            r ~= s;
    }

    while (s.length)
    {
        if (s.startsWith("\\L"))
        {
            caseChange = -1;
            s = s[2 .. $];
            continue;
        }
        if (s.startsWith("\\U"))
        {
            caseChange = 1;
            s = s[2 .. $];
            continue;
        }
        if (s.startsWith("\\E"))
        {
            caseChange = 0;
            s = s[2 .. $];
            continue;
        }

        if (s.startsWith("%") && s.length >= 2)
        {
            if (pattern.filename.namedCaptures.canFind(s[1 .. 2]))
            {
                append(match.filenameMatch[s[1 .. 2]]);
                s = s[2 .. $];
                continue;
            }
            if (pattern.name.namedCaptures.canFind(s[1 .. 2]))
            {
                append(match.nameMatch[s[1 .. 2]]);
                s = s[2 .. $];
                continue;
            }
        }
        if (s.startsWith("%B"))
        {
            append(match.filenameMatch.captures[0].baseName.stripExtension);
            s = s[2 .. $];
        }
        else
        {
            size_t len = s.stride;
            append(s[0 .. len]);
            s = s[len .. $];
        }
    }
    return r;
}

void findUnusedPatterns(T)(ref T config, string path = "")
{
    static if (is(T == ConfigRegex))
    {
    }
    else static if (is(T == DeclarationPattern))
    {
        if (!config.used || config.redundant)
        {
            writeln(config.redundant ? "Redundant" : "Unused", " pattern at ", path, ":",
                config.name.pattern.length ? " name=" : "", config.name.pattern,
                config.filename.pattern.length ? " filename=" : "", config.filename.pattern,
                config.lines.length ? text(" lines=", config.lines) : "",
                " isTemplate=", config.isTemplate,
                " inMacro=", config.inMacro);
        }
    }
    else static if (is(T == struct))
    {
        static foreach (member; T.tupleof)
        {{
            enum memberName = __traits(identifier, member);
            static assert(memberName != "include", "Config member include is reserved");
            findUnusedPatterns(__traits(getMember, config, memberName), text(path, path.length ? "." : "", memberName));
        }}
    }
    else static if (is(T == C[], C))
    {
        foreach (i, ref c; config)
            findUnusedPatterns(c, text(path, "[", i, "]"));
    }
    else static if (is(T == C[string], C))
    {
        foreach (k, ref c; config)
            findUnusedPatterns(c, text(path, "[\"", k.escapeD, "\"]"));
    }
}
