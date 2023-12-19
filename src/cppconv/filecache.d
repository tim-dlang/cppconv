
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.filecache;
import cppconv.common;
import cppconv.cpptree;
import cppconv.locationstack;
import cppconv.preprocparserwrapper;
import dparsergen.core.nodetype;
import dparsergen.core.parseexception;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.typecons;

alias Location = LocationX;

alias Tree = CppParseTree;

struct RealFilename
{
    string name;
}

struct VirtualFilename
{
    string name;
}

struct LocConditions
{
    struct Entry
    {
        LocationN end;
        immutable(Formula)* condition;
    }

    Entry[] entries;

    LocationN lastEnd()
    {
        if (entries.length)
            return entries[$ - 1].end;
        return LocationN.init;
    }

    void add(LocationN start, LocationN end, immutable(Formula)* condition)
    {
        if (entries.length)
        {
            assert(start == entries[$ - 1].end, text(start, " ", entries[$ - 1].end));
            if (entries[$ - 1].condition is condition)
            {
                entries[$ - 1].end = end;
            }
            else
            {
                entries ~= Entry(end, condition);
            }
        }
        else
        {
            assert(start == LocationN.init);
            entries ~= Entry(end, condition);
        }
    }

    void merge(immutable(Formula)* conditionUsed1, const LocConditions other,
            immutable(Formula)* conditionUsed2, LogicSystem logicSystem)
    {
        Entry[] entries1 = entries;
        const(Entry)[] entries2 = other.entries;
        entries = [];
        LocationN last;
        immutable(Formula)* contextCondition = logicSystem.or(conditionUsed1, conditionUsed2);
        while (entries1.length && entries2.length)
        {
            immutable(Formula)* c1 = logicSystem.and(conditionUsed1, entries1[0].condition);
            immutable(Formula)* c2 = logicSystem.and(conditionUsed2, entries2[0].condition);
            immutable(Formula)* c = logicSystem.removeRedundant(logicSystem.or(c1,
                    c2), contextCondition);
            if (entries1[0].end == entries2[0].end)
            {
                add(last, entries1[0].end, c);
                last = entries1[0].end;
                entries1 = entries1[1 .. $];
                entries2 = entries2[1 .. $];
            }
            else if (entries1[0].end < entries2[0].end)
            {
                add(last, entries1[0].end, c);
                last = entries1[0].end;
                entries1 = entries1[1 .. $];
            }
            else
            {
                add(last, entries2[0].end, c);
                last = entries2[0].end;
                entries2 = entries2[1 .. $];
            }
        }
        while (entries1.length)
        {
            immutable(Formula)* c1 = logicSystem.and(conditionUsed1, entries1[0].condition);
            c1 = logicSystem.removeRedundant(c1, contextCondition);
            add(last, entries1[0].end, c1);
            last = entries1[0].end;
            entries1 = entries1[1 .. $];
        }
        while (entries2.length)
        {
            immutable(Formula)* c2 = logicSystem.and(conditionUsed2, entries2[0].condition);
            c2 = logicSystem.removeRedundant(c2, contextCondition);
            add(last, entries2[0].end, c2);
            last = entries2[0].end;
            entries2 = entries2[1 .. $];
        }
    }

    immutable(Formula)* find(LocationN start, LocationN end)
    {
        LocationN lastEnd = LocationN.init;
        foreach (e; entries)
        {
            if (start >= lastEnd && end <= e.end)
                return e.condition;
            lastEnd = e.end;
        }
        assert(false, text(start, "\n", end, "\n", lastEnd));
    }
}

class FileData
{
    Tree tree;
    Location startLocation;
    bool notFound;
    bool triedLoading;
    RealFilename[] including;
    bool includeGraphDone;
    int includeGraphDoing;
    bool includeGraphRecursive;
}

struct IncludeDir
{
    string path;
    immutable(Formula)* condition;
    bool used;
}

class FileCache
{
    FileData[RealFilename] files;

    IncludeDir[] includeDirs;
    size_t origIncludeDirsSize;
    RealFilename[] alwaysIncludeFiles;

    FileData getFileNoLoad(RealFilename realFilename)
    {
        LocationX location = LocationX(LocationN(), new immutable(LocationContext)(null,
                LocationN(), LocationN.LocationDiff(), "", realFilename.name, true));
        FileData fileData;
        if (realFilename !in files)
        {
            fileData = new FileData();
            files[realFilename] = fileData;

            fileData.startLocation = location;
        }
        else
        {
            fileData = files[realFilename];
            assert(fileData.startLocation.context.filename == location.context.filename,
                    text(realFilename, " ", locationStr(fileData.startLocation),
                        "  ", locationStr(location)));
        }
        return fileData;
    }

    FileData getFile(RealFilename realFilename)
    {
        FileData fileData = getFileNoLoad(realFilename);
        if (fileData.triedLoading)
            return fileData;

        writeln("loading file \"", realFilename.name, "\"");

        string inText;
        try
        {
            inText = readText(realFilename.name);
        }
        catch (FileException e)
        {
            fileData.notFound = true;
        }

        if (!fileData.notFound)
        {
            try
            {
                fileData.tree = preprocParse(inText, fileData.startLocation,
                        preprocTreeAllocator, &globalStringPool);
                assert(fileData.tree.inputLength.bytePos <= inText.length);
            }
            catch (ParseException e)
            {
                stderr.writeln("========= File ", realFilename, " ============");
                throw e;
            }
            import core.memory;

            GC.free(cast(void*) inText.ptr);
        }
        fileData.triedLoading = true;

        return fileData;
    }

    Tuple!(RealFilename, immutable(Formula)*)[] lookupFilename(VirtualFilename filename,
            RealFilename currentFilename, immutable(Formula)* condition, LogicSystem logicSystem)
    {
        if (condition.isFalse)
            return [];
        while (currentFilename.name.length)
        {
            if (currentFilename.name[$ - 1] == '/')
            {
                break;
            }
            currentFilename.name = currentFilename.name[0 .. $ - 1];
        }

        //if (currentFilename.name.length && currentFilename.name[$-1] == '/')
        {
            string filename2 = buildNormalizedPath(currentFilename.name ~ filename.name)
                    .replace("\\", "/");
            if (std.file.exists(filename2) && std.file.isFile(filename2))
            {
                return [
                    tuple!(RealFilename, immutable(Formula)*)(RealFilename(filename2), condition)
                ];
            }
        }

        Tuple!(RealFilename, immutable(Formula)*)[] r;
        foreach (ref d; includeDirs)
        {
            immutable(Formula)* condition2 = logicSystem.and(condition, d.condition);
            if (condition2.isFalse)
                continue;
            string filename2 = buildNormalizedPath(d.path ~ "/" ~ filename.name).replace("\\", "/");
            if (std.file.exists(filename2) && std.file.isFile(filename2))
            {
                r ~= tuple!(RealFilename, immutable(Formula)*)(RealFilename(filename2), condition2);
                d.used = true;
                condition = logicSystem.and(condition, d.condition.negated);
            }
        }
        return r;
    }

    Tuple!(RealFilename, immutable(Formula)*)[] lookupFilenameNext(VirtualFilename filename,
            RealFilename currentFilename, immutable(Formula)* condition, LogicSystem logicSystem)
    {
        bool foundCurrent;
        Tuple!(RealFilename, immutable(Formula)*)[] r;
        foreach (ref d; includeDirs)
        {
            string filename2 = buildNormalizedPath(d.path ~ "/" ~ filename.name).replace("\\", "/");
            if (!foundCurrent)
            {
                if (filename2 == currentFilename.name
                        || currentFilename.name.startsWith(buildNormalizedPath(d.path)
                            .replace("\\", "/") ~ "/"))
                    foundCurrent = true;
            }
            else
            {
                immutable(Formula)* condition2 = logicSystem.and(condition, d.condition);
                if (condition2.isFalse)
                    continue;
                if (std.file.exists(filename2))
                {
                    r ~= tuple!(RealFilename, immutable(Formula)*)(RealFilename(filename2),
                            condition2);
                    d.used = true;
                    condition = logicSystem.and(condition, d.condition.negated);
                }
            }
        }
        return r;
    }
}
