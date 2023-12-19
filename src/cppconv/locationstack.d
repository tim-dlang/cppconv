
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.locationstack;
import dparsergen.core.location;
import std.algorithm;
import std.array;
import std.conv;

alias LocationN = LocationImpl!(LocationTypeFlags.bytes | LocationTypeFlags.lines | LocationTypeFlags.lineOffset);

string locationStr(LocationN l)
{
    return text(l.line + 1, ":", l.offset + 1);
}

string locationStr(LocationX l, bool isEnd = false)
{
    Appender!string app;
    locationStr(app, l, isEnd);
    return app.data;
}

void locationStr(O)(ref O outRange, LocationX l, bool isEnd = false)
{
    if (l.context is null)
    {
        if (l.loc == LocationN.invalid)
        {
            outRange.put("???");
            return;
        }
        outRange.put(text(l.line + 1, ":", l.offset + 1));
        return;
    }

    import std.format;

    auto spec = singleSpec("%s");

    void visitContext(immutable(LocationContext)* c, LocationN loc)
    {
        if (c.prev !is null)
        {
            visitContext(c.prev, isEnd ? (c.startInPrev + c.lengthInPrev) : c.startInPrev);
            outRange.put("/");
        }
        if (c.name.length)
        {
            outRange.put(c.name);
            outRange.put("@");
        }
        if (c.isPreprocLocation)
            outRange.put("#");
        outRange.put(c.filename);
        outRange.put(":");
        if (loc.line >= typeof(LocationN.LocationDiff.line).max)
            outRange.put("??");
        else
            outRange.formatValue(loc.line + 1, spec);
        outRange.put(":");
        if (loc.offset >= typeof(LocationN.LocationDiff.offset).max)
            outRange.put("??");
        else
            outRange.formatValue(loc.offset + 1, spec);
    }

    visitContext(l.context, l.loc);
}

string locationStr(LocationRangeX l)
{
    Appender!string app;
    locationStr(app, l);
    return app.data;
}

void locationStr(O)(ref O outRange, LocationRangeX l)
{
    if (l.context is null)
    {
        if (l.start.loc == LocationN.invalid)
        {
            outRange.put("???");
            return;
        }
        outRange.put(text(l.start.line + 1, ":", l.start.offset + 1));
        return;
    }

    import std.format;

    auto spec = singleSpec("%s");

    void visitContext(immutable(LocationContext)* c, LocationN loc, LocationN end)
    {
        if (c.prev !is null)
        {
            visitContext(c.prev, c.startInPrev, c.startInPrev + c.lengthInPrev);
            outRange.put("/");
        }
        if (c.name.length)
        {
            outRange.put(c.name);
            outRange.put("@");
        }
        if (c.isPreprocLocation)
            outRange.put("#");
        outRange.put(c.filename);

        outRange.put(":");
        if (loc.line >= typeof(LocationN.LocationDiff.line).max)
            outRange.put("??");
        else
            outRange.formatValue(loc.line + 1, spec);
        outRange.put(":");
        if (loc.offset >= typeof(LocationN.LocationDiff.offset).max)
            outRange.put("??");
        else
            outRange.formatValue(loc.offset + 1, spec);

        outRange.put("~");
        if (end.line >= typeof(LocationN.LocationDiff.line).max)
            outRange.put("??");
        else
            outRange.formatValue(end.line + 1, spec);
        outRange.put(":");
        if (end.offset >= typeof(LocationN.LocationDiff.offset).max)
            outRange.put("??");
        else
            outRange.formatValue(end.offset + 1, spec);
    }

    visitContext(l.context, l.start.loc, l.end.loc);
}

string locationStr(immutable(LocationContext)* lc)
{
    auto r = locationStr(LocationRangeX(LocationX(LocationN.init, lc), LocationN.LocationDiff.init));
    immutable suffix = ":1:1~1:1";
    assert(r.endsWith(suffix));
    return r[0 .. $ - suffix.length];
}

struct LocationContext
{
    LocationContext* prev;
    LocationN startInPrev;
    LocationN.LocationDiff lengthInPrev;
    string name; // macro name / macro parameter name
    string filename;
    ushort contextDepth;
    bool isPreprocLocation;

    this(immutable LocationContext* prev, LocationN startInPrev, LocationN.LocationDiff lengthInPrev,
            string name, string filename, bool isPreprocLocation = false) immutable
    in
    {
        if (prev !is null)
            assert(isPreprocLocation == prev.isPreprocLocation);
    }
    do
    {
        this.prev = prev;
        this.startInPrev = startInPrev;
        this.lengthInPrev = lengthInPrev;
        this.name = name;
        this.filename = filename;
        this.isPreprocLocation = isPreprocLocation;
        if (prev is null)
            this.contextDepth = 1;
        else
            this.contextDepth = cast(ushort)(prev.contextDepth + 1);
    }

    LocationRangeX parentLocation() immutable
    {
        return LocationRangeX(LocationX(startInPrev, prev), lengthInPrev);
    }
}

struct LocationX
{
    immutable(LocationContext)* context;
    LocationN loc;
    alias LocationDiff = LocationN.LocationDiff;

    this(LocationN loc, immutable(LocationContext)* context = null)
    {
        this.context = context;
        this.loc = loc;
    }

    auto bytePos() const
    {
        return loc.bytePos;
    }

    auto line() const
    {
        return loc.line;
    }

    auto offset() const
    {
        return loc.offset;
    }

    size_t contextDepth() const
    {
        if (context is null)
            return 0;
        else
            return context.contextDepth;
    }

    enum max = LocationX(LocationN.max);
    enum invalid = LocationX(LocationN.invalid);

    bool isValid() const
    {
        return loc.isValid /* && context !is null*/ ;
    }

    LocationDiff opBinary(string op)(const LocationX rhs) const if (op == "-")
    {
        if (rhs.context is context)
            return loc - rhs.loc;
        else
            return LocationDiff.invalid;
    }

    LocationX opBinary(string op)(const LocationDiff rhs) const if (op == "+")
    {
        if (!this.isValid || !rhs.isValid)
            return invalid;
        else
            return LocationX(loc + rhs, context);
    }

    int opCmp(const LocationX rhs) const
    {
        return opCmp2(rhs, false);
    }

    int opCmp2(const LocationX rhs, bool handleNulls) const
    {
        LocationRangeX prevA, prevB;
        LocationRangeX a = LocationRangeX(this);
        LocationRangeX b = LocationRangeX(rhs);
        findCommonLocationContext(a, b, &prevA, &prevB);
        if (a.end.loc < b.start.loc)
            return -1;
        if (a.start.loc > b.end.loc)
            return 1;
        if (a.inputLength > LocationDiff.zero || b.inputLength > LocationDiff.zero)
        {
            if (a.end.loc <= b.start.loc)
                return -2;
            if (a.start.loc >= b.end.loc)
                return 2;
            if (a.start.loc < b.start.loc)
                return -3;
            if (a.start.loc > b.start.loc)
                return 3;
            if (a.end.loc < b.end.loc)
                return -4;
            if (a.end.loc > b.end.loc)
                return 4;
        }
        if (handleNulls)
        {
            if (prevA.context is null && prevB.context !is null)
                return -5;
            if (prevA.context !is null && prevB.context is null)
                return 5;
            if (prevA.context !is null && prevB.context !is null)
            {
                if (prevA.context.filename < prevB.context.filename)
                    return -6;
                if (prevA.context.filename > prevB.context.filename)
                    return 6;
            }
        }
        if (context !is null && rhs.context !is null
                && context.isPreprocLocation < rhs.context.isPreprocLocation)
            return -1;
        if (context !is null && rhs.context !is null
                && context.isPreprocLocation > rhs.context.isPreprocLocation)
            return 1;
        return 0;
    }

    static LocationX fromStr(string s)
    {
        return LocationX(LocationN.fromStr(s));
    }
}

LocationX minLoc(LocationX a, LocationX b)
{
    if (a == LocationX.invalid)
        return b;
    if (b == LocationX.invalid)
        return a;
    if (a < b)
        return a;
    return b;
}

LocationX maxLoc(LocationX a, LocationX b)
{
    if (a == LocationX.invalid)
        return b;
    if (b == LocationX.invalid)
        return a;
    if (a > b)
        return a;
    return b;
}

void findCommonLocationContext(ref LocationX a, ref LocationX b)
{
    while (a.contextDepth > b.contextDepth)
        a = a.context.parentLocation.start;
    while (b.contextDepth > a.contextDepth)
        b = b.context.parentLocation.start;
    while (a.context !is b.context)
    {
        assert(a.contextDepth == b.contextDepth);
        a = a.context.parentLocation.start;
        b = b.context.parentLocation.start;
    }
}

void findCommonLocationContext2(ref LocationX a, ref LocationX b)
{
    while (a.contextDepth > b.contextDepth)
        a = a.context.parentLocation.start;
    while (b.contextDepth > a.contextDepth)
        b = b.context.parentLocation.end;
    while (a.context !is b.context)
    {
        assert(a.contextDepth == b.contextDepth);
        a = a.context.parentLocation.start;
        b = b.context.parentLocation.end;
    }
}

void findCommonLocationContext(ref LocationRangeX a, ref LocationRangeX b,
        LocationRangeX* prevA = null, LocationRangeX* prevB = null)
{
    LocationRangeX pa, pb;
    while (a.start.contextDepth > b.start.contextDepth)
    {
        pa = a;
        a = a.context.parentLocation;
    }
    while (b.start.contextDepth > a.start.contextDepth)
    {
        pb = b;
        b = b.context.parentLocation;
    }
    while (a.context !is b.context)
    {
        assert(a.start.contextDepth == b.start.contextDepth);
        pa = a;
        pb = b;
        a = a.context.parentLocation;
        b = b.context.parentLocation;
    }
    if (prevA !is null)
        *prevA = pa;
    if (prevB !is null)
        *prevB = pb;
}

struct LocationRangeX
{
    alias LocationDiff = LocationN.LocationDiff;
    private immutable(LocationContext)* context_;
    LocationN start_;
    LocationN.LocationDiff inputLength_;

    this(LocationX start, LocationN.LocationDiff inputLength = LocationN.LocationDiff.init)
    {
        this.context_ = start.context;
        this.start_ = start.loc;
        this.inputLength_ = inputLength;
    }

    enum invalid = LocationRangeX(LocationX.invalid, LocationN.LocationDiff.invalid);

    LocationN end_() const
    {
        return start_ + inputLength_;
    }

    LocationX start() const
    {
        return LocationX(start_, context_);
    }

    LocationX end() const
    {
        return LocationX(start_ + inputLength_, context_);
    }

    LocationDiff inputLength() const
    {
        return inputLength_;
    }

    immutable(LocationContext)* context() const
    {
        return context_;
    }

    void setStartEnd(LocationX start, LocationX end)
    {
        findCommonLocationContext2(start, end);
        this.context_ = start.context;
        this.start_ = start.loc;
        this.inputLength_ = end - start;
    }

    void setStartLength(LocationX start, LocationDiff inputLength)
    {
        this.context_ = start.context;
        this.start_ = start.loc;
        this.inputLength_ = inputLength;
    }
}

template LocationRangeXW(Location) if (is(Location == LocationX))
{
    alias LocationRangeXW = LocationRangeX;
}

LocationRangeX mergeLocationRanges(LocationRangeX a, LocationRangeX b)
{
    LocationX startA = a.start;
    LocationX endA = a.end;
    LocationX startB = b.start;
    LocationX endB = b.end;
    if (startB < startA)
        startA = startB;
    if (endB > endA)
        endA = endB;
    findCommonLocationContext(startA, endA);
    return LocationRangeX(startA, endA - startA);
}

LocationX reparentLocation(LocationX l, immutable LocationContext* parent)
in
{
    assert(l.context.filename == parent.filename, text(l.context.filename, " ", parent.filename));
}
do
{
    return LocationX(l.loc, parent);
}

void mapLocations(Tree)(Tree tree, immutable LocationContext* newContext,
        LocationN.LocationDiff diff)
{
    if (!tree.isValid)
        return;
    tree.location.setStartLength(LocationX(LocationN(tree.start.loc.bytePos + diff.bytePos,
            tree.start.loc.line + diff.line, tree.start.loc.offset), newContext), tree.inputLength);
    foreach (child; tree.childs)
        mapLocations!Tree(child, newContext, diff);
}

LocationRangeX nonMacroLocation(LocationRangeX a)
{
    while (a.context !is null && a.context.name.length)
        a = a.context.parentLocation;
    return a;
}

LocationX nonMacroLocation(LocationX a)
{
    while (a.context !is null && a.context.name.length)
        a = a.context.parentLocation.start;
    return a;
}

string rootFilename(immutable(LocationContext)* a)
{
    if (a is null)
        return "";
    while (a.prev !is null)
        a = a.prev;
    return a.filename;
}

static size_t numLocationContextsCreated;
class LocationContextMap
{
    immutable(LocationContext)*[immutable(LocationContext)] locationContextMap;
    immutable(LocationContext)* getLocationContext(immutable(LocationContext) c)
    {
        auto x = c in locationContextMap;
        if (x)
            return *x;

        auto r = new immutable(LocationContext)(c.prev, c.startInPrev,
                c.lengthInPrev, c.name, c.filename, c.isPreprocLocation);
        validateLocationContext(r);
        locationContextMap[c] = r;
        numLocationContextsCreated++;
        return r;
    }
}

immutable(LocationContext)* stackLocations(immutable(LocationContext)* a,
        immutable(LocationContext)* b, LocationContextMap locationContextMap)
{
    if (b.prev is null)
    {
        assert(a.filename == b.filename);
        return a;
    }
    return locationContextMap.getLocationContext(immutable(LocationContext)(stackLocations(a,
            b.prev, locationContextMap), b.startInPrev, b.lengthInPrev, b.name,
            b.filename, b.isPreprocLocation));
}

LocationX stackLocations(immutable(LocationContext)* a, LocationX b,
        LocationContextMap locationContextMap)
{
    return LocationX(b.loc, stackLocations(a, b.context, locationContextMap));
}

immutable(LocationContext)* unstackLocations(immutable(LocationContext)* a,
        immutable(LocationContext)* b, LocationContextMap locationContextMap)
{
    if (b is a)
    {
        return null;
    }
    auto newPrev = unstackLocations(a, b.prev, locationContextMap);
    if (newPrev is null)
        return locationContextMap.getLocationContext(immutable(LocationContext)(newPrev, LocationN.init,
                LocationN.LocationDiff.init, b.name, b.filename, b.isPreprocLocation));
    else
        return locationContextMap.getLocationContext(immutable(LocationContext)(newPrev,
                b.startInPrev, b.lengthInPrev, b.name, b.filename, b.isPreprocLocation));
}

LocationX unstackLocations(immutable(LocationContext)* a, LocationX b,
        LocationContextMap locationContextMap)
{
    return LocationX(b.loc, unstackLocations(a, b.context, locationContextMap));
}

immutable(LocationContext)* macroFromParam(immutable(LocationContext)* lc)
{
    //assert(lc.filename.length == 0);
    string macroName = lc.name;
    string paramName;
    foreach (i, char c; macroName)
    {
        if (c == '.')
        {
            paramName = macroName[i + 1 .. $];
            macroName = macroName[0 .. i];
            break;
        }
    }
    assert(paramName.length);
    immutable(LocationContext)* lc2 = lc.prev;
    while (lc2.name.among("##", "#"))
        lc2 = lc2.prev;
    assert(lc2.name == "^");
    assert(lc2.filename.length);
    //assert(lc2.prev.filename.length == 0);
    while (lc2.prev.name.canFind("."))
    {
        lc2 = macroFromParam(lc2.prev);
        assert(lc2.name == "^");
        if (lc2.prev.name.canFind("^"))
        {
            lc2 = lc2.prev.prev.prev.prev.prev;
            break;
        }
        lc2 = lc2.prev.prev.prev;
        while (lc2.name == "##")
            lc2 = lc2.prev;
    }
    assert(lc2.prev.name == macroName, text(lc2.prev.name, " ", macroName));
    assert(lc2.prev.prev.name == macroName, text(lc2.prev.prev.name, " ", macroName));
    return lc2;
}

void validateLocationContext(immutable(LocationContext)* locationContext)
{
    immutable(LocationContext)* lc = locationContext;
    assert(lc !is null);
    while (lc !is null)
    {
        if (lc.name == "##")
        {
            if (lc.filename == "@concat")
            {
                lc = lc.prev;
            }
            if (lc.name == "##")
            {
                lc = lc.prev;
                assert(lc.name.among("^", "##"));
            }
        }
        else if (lc.name == "^")
        {
            assert(lc.prev.name.length && lc.prev.name != "^",
                    text(locationStr(LocationX(LocationN(), locationContext))));
            lc = lc.prev;
        }
        else if (lc.name.canFind("."))
        {
            lc = macroFromParam(lc).prev;
        }
        else if (lc.name.length)
        {
            immutable(LocationContext)* prev = lc.prev;
            while (prev.name == "##")
                prev = prev.prev;
            if (prev.name == "^")
            {
                lc = prev.prev;
            }
            else if (prev.name.length)
            {
                assert(prev.name == lc.name, text(prev.name, " ", lc.name, "\n",
                        locationStr(LocationX(LocationN(), locationContext)),
                        "\n", locationStr(LocationX(LocationN(), lc)),));
                lc = prev.prev;
                assert(lc.name.among("", "^", "##"));
            }
            else
            {
                lc = prev;
            }
        }
        else
        {
            break;
        }
    }
    while (lc !is null)
    {
        assert(lc.name == "");
        lc = lc.prev;
    }
}

bool isParentOf(immutable(LocationContext)* a, immutable(LocationContext)* b)
{
    if (a is null)
        return true;
    if (b is null)
        return false;
    if (a.contextDepth > b.contextDepth)
        return false;
    while (a.contextDepth < b.contextDepth)
        b = b.prev;
    return a is b;
}
