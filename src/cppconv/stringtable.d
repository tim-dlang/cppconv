/**
 * A specialized associative array with string keys stored in a variable length structure.
 *
 * Copyright: Copyright (C) 1999-2020 by The D Language Foundation, all Rights Reserved
 * Authors:   Walter Bright, http://www.digitalmars.com
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:    $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/root/stringtable.d, root/_stringtable.d)
 * Documentation:  https://dlang.org/phobos/dmd_root_stringtable.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/root/stringtable.d
 */

module cppconv.stringtable;

import core.exception : onOutOfMemoryError;
import core.memory;
import core.stdc.string;
import cppconv.hash;

private enum POOL_BITS = 12;
private enum POOL_SIZE = (1U << POOL_BITS);

static void* error() pure nothrow @nogc
{
    onOutOfMemoryError();
    assert(0);
}

/**
 * Check p for null. If it is, issue out of memory error
 * and exit program.
 * Params:
 *  p = pointer to check for null
 * Returns:
 *  p if not null
 */
static void* check(void* p) pure nothrow @nogc
{
    return p ? p : error();
}

/*
Returns the smallest integer power of 2 larger than val.
if val > 2^^63 on 64-bit targets or val > 2^^31 on 32-bit targets it enters an
endless loop because of overflow.
*/
private size_t nextpow2(size_t val) @nogc nothrow pure @safe
{
    size_t res = 1;
    while (res < val)
        res <<= 1;
    return res;
}

unittest
{
    assert(nextpow2(0) == 1);
    assert(nextpow2(0xFFFF) == (1 << 16));
    assert(nextpow2(size_t.max / 2) == size_t.max / 2 + 1);
    // note: nextpow2((1UL << 63) + 1) results in an endless loop
}

private enum loadFactorNumerator = 8;
private enum loadFactorDenominator = 10; // for a load factor of 0.8

private struct StringEntry
{
    uint hash;
    uint vptr;
}

enum bool ADD_TERMINATING_ZERO = false;

// StringValue is a variable-length structure. It has neither proper c'tors nor a
// factory method because the only thing which should be creating these is StringTable.
struct StringValue(T)
{
    T value; //T is/should typically be a pointer or a slice
    private uint length;

    static if (ADD_TERMINATING_ZERO)
        char* lstring() @nogc nothrow pure return
        {
            return cast(char*)(&this + 1);
        }

    size_t len() const @nogc nothrow pure @safe
    {
        return length;
    }

    static if (ADD_TERMINATING_ZERO)
        const(char)* toDchars() const @nogc nothrow pure return
        {
            return cast(const(char)*)(&this + 1);
        }

    /// Returns: The content of this entry as a D slice
    inout(char)[] toString() inout @nogc nothrow pure
    {
        return (cast(inout(char)*)(&this + 1))[0 .. length];
    }
}

struct StringTable(T)
{
private:
    StringEntry[] table;
    ubyte*[] pools;
    struct PoolBlock
    {
        size_t index;
        size_t nfill;
    }

    PoolBlock[2] poolBlocks;
    size_t count;
    size_t countTrigger; // amount which will trigger growing the table

public:
    void _init(size_t size = 0) nothrow pure
    {
        size = nextpow2((size * loadFactorDenominator) / loadFactorNumerator);
        if (size < 32)
            size = 32;
        table = (cast(StringEntry*) check(pureCalloc(size, (table[0]).sizeof)))[0 .. size];
        countTrigger = (table.length * loadFactorNumerator) / loadFactorDenominator;
        pools = null;
        foreach (ref b; poolBlocks)
        {
            b.index = size_t.max;
            b.nfill = 0;
        }
        count = 0;
    }

    void reset(size_t size = 0) nothrow pure
    {
        freeMem();
        _init(size);
    }

    ~this() nothrow pure
    {
        freeMem();
    }

    /**
    Looks up the given string in the string table and returns its associated
    value.

    Params:
     s = the string to look up
     length = the length of $(D_PARAM s)
     str = the string to look up

    Returns: the string's associated value, or `null` if the string doesn't
     exist in the string table
    */
    inout(StringValue!T)* lookup(const(char)[] str) inout @nogc nothrow pure
    {
        const(size_t) hash = calcHash(str);
        const(size_t) i = findSlot(hash, str);
        // printf("lookup %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: null);
        return getValue(table[i].vptr);
    }

    /// ditto
    inout(StringValue!T)* lookup(const(char)* s, size_t length) inout @nogc nothrow pure
    {
        return lookup(s[0 .. length]);
    }

    /**
    Inserts the given string and the given associated value into the string
    table.

    Params:
     s = the string to insert
     length = the length of $(D_PARAM s)
     ptrvalue = the value to associate with the inserted string
     str = the string to insert
     value = the value to associate with the inserted string

    Returns: the newly inserted value, or `null` if the string table already
     contains the string
    */
    StringValue!(T)* insert(const(char)[] str, T value) nothrow pure
    {
        const(size_t) hash = calcHash(str);
        size_t i = findSlot(hash, str);
        if (table[i].vptr)
            return null; // already in table
        if (++count > countTrigger)
        {
            grow();
            i = findSlot(hash, str);
        }
        table[i].hash = hash;
        table[i].vptr = allocValue(str, value);
        // printf("insert %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: NULL);
        return getValue(table[i].vptr);
    }

    /// ditto
    StringValue!(T)* insert(const(char)* s, size_t length, T value) nothrow pure
    {
        return insert(s[0 .. length], value);
    }

    StringValue!(T)* update(const(char)[] str) nothrow pure
    {
        const(size_t) hash = calcHash(str);
        size_t i = findSlot(hash, str);
        if (!table[i].vptr)
        {
            if (++count > countTrigger)
            {
                grow();
                i = findSlot(hash, str);
            }
            table[i].hash = hash;
            table[i].vptr = allocValue(str, T.init);
        }
        // printf("update %.*s %p\n", cast(int)str.length, str.ptr, table[i].value ?: NULL);
        return getValue(table[i].vptr);
    }

    StringValue!(T)* update(const(char)* s, size_t length) nothrow pure
    {
        return update(s[0 .. length]);
    }

    /********************************
     * Walk the contents of the string table,
     * calling fp for each entry.
     * Params:
     *      fp = function to call. Returns !=0 to stop
     * Returns:
     *      last return value of fp call
     */
    int apply(int function(const(StringValue!T)*) nothrow fp) nothrow
    {
        foreach (const se; table)
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            int result = (*fp)(sv);
            if (result)
                return result;
        }
        return 0;
    }

    /// ditto
    extern (D) int opApply(scope int delegate(const(StringValue!T)*) nothrow dg) nothrow
    {
        foreach (const se; table)
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            int result = dg(sv);
            if (result)
                return result;
        }
        return 0;
    }

private:
    /// Free all memory in use by this StringTable
    void freeMem() nothrow pure
    {
        foreach (pool; pools)
            pureFree(pool);
        pureFree(table.ptr);
        pureFree(pools.ptr);
        table = null;
        pools = null;
    }

    uint allocValue(const(char)[] str, T value) nothrow pure
    {
        if (str.length > typeof(StringValue!(T).init.length).max)
            assert(0);
        const(size_t) nbytes = (StringValue!T).sizeof + str.length + ADD_TERMINATING_ZERO;

        size_t bestPool = size_t.max;
        foreach (i, ref b; poolBlocks)
        {
            if (b.index < pools.length && b.nfill + nbytes <= POOL_SIZE)
            {
                bestPool = i;
                break;
            }
        }
        if (bestPool == size_t.max)
        {
            size_t fullest = 0;
            foreach (i, ref b; poolBlocks)
            {
                if (b.index == size_t.max)
                {
                    bestPool = i;
                    break;
                }
                if (b.nfill > fullest)
                {
                    fullest = b.nfill;
                    bestPool = i;
                }
            }
            foreach (i; bestPool .. poolBlocks.length - 1)
            {
                poolBlocks[i] = poolBlocks[i + 1];
            }
            bestPool = poolBlocks.length - 1;

            pools = (cast(ubyte**) check(pureRealloc(pools.ptr,
                    (pools.length + 1) * (pools[0]).sizeof)))[0 .. pools.length + 1];
            pools[$ - 1] = cast(ubyte*) check(pureMalloc(nbytes > POOL_SIZE ? nbytes : POOL_SIZE));
            /*if (mem.isGCEnabled)
                memset(pools[$ - 1], 0xff, POOL_SIZE);*/ // 0xff less likely to produce GC pointer
            poolBlocks[bestPool].index = pools.length - 1;
            poolBlocks[bestPool].nfill = 0;
        }
        StringValue!(T)* sv = cast(StringValue!(T)*)&pools[poolBlocks[bestPool].index][poolBlocks[bestPool]
                .nfill];
        sv.value = value;
        sv.length = cast(typeof(StringValue!(T).init.length)) str.length;
        .memcpy(sv.toString().ptr, str.ptr, str.length);
        static if (ADD_TERMINATING_ZERO)
            sv.lstring()[str.length] = 0;
        const(uint) vptr = cast(uint)(
                (poolBlocks[bestPool].index + 1) << POOL_BITS | poolBlocks[bestPool].nfill);
        static if (typeof(StringValue!(T).init.length).sizeof == 4)
            poolBlocks[bestPool].nfill += nbytes + (-nbytes & 3); // align to 4 bytes
        else
            poolBlocks[bestPool].nfill += nbytes + (-nbytes & 7); // align to 8 bytes
        return vptr;
    }

    inout(StringValue!T)* getValue(uint vptr) inout @nogc nothrow pure
    {
        if (!vptr)
            return null;
        const(size_t) idx = (vptr >> POOL_BITS) - 1;
        const(size_t) off = vptr & POOL_SIZE - 1;
        return cast(inout(StringValue!T)*)&pools[idx][off];
    }

    size_t findSlot(hash_t hash, const(char)[] str) const @nogc nothrow pure
    {
        // quadratic probing using triangular numbers
        // http://stackoverflow.com/questions/2348187/moving-from-linear-probing-to-quadratic-probing-hash-collisons/2349774#2349774
        for (size_t i = hash & (table.length - 1), j = 1;; ++j)
        {
            const(StringValue!T)* sv;
            auto vptr = table[i].vptr;
            if (!vptr || table[i].hash == hash && (sv = getValue(vptr))
                    .length == str.length && .memcmp(str.ptr, sv.toString().ptr, str.length) == 0)
                return i;
            i = (i + j) & (table.length - 1);
        }
    }

    void grow() nothrow pure
    {
        const odim = table.length;
        auto otab = table;
        const ndim = table.length * 2;
        countTrigger = (ndim * loadFactorNumerator) / loadFactorDenominator;
        table = (cast(StringEntry*) check(pureCalloc(ndim, (table[0]).sizeof)))[0 .. ndim];
        foreach (const se; otab[0 .. odim])
        {
            if (!se.vptr)
                continue;
            const sv = getValue(se.vptr);
            table[findSlot(se.hash, sv.toString())] = se;
        }
        pureFree(otab.ptr);
    }
}

nothrow unittest
{
    StringTable!(const(char)*) tab;
    tab._init(10);

    // construct two strings with the same text, but a different pointer
    const(char)[6] fooBuffer = "foofoo";
    const(char)[] foo = fooBuffer[0 .. 3];
    const(char)[] fooAltPtr = fooBuffer[3 .. 6];

    assert(foo.ptr != fooAltPtr.ptr);

    // first insertion returns value
    assert(tab.insert(foo, foo.ptr).value == foo.ptr);

    // subsequent insertion of same string return null
    assert(tab.insert(foo.ptr, foo.length, foo.ptr) == null);
    assert(tab.insert(fooAltPtr, foo.ptr) == null);

    const lookup = tab.lookup("foo");
    assert(lookup.value == foo.ptr);
    assert(lookup.len == 3);
    assert(lookup.toString() == "foo");

    assert(tab.lookup("bar") == null);
    tab.update("bar".ptr, "bar".length);
    assert(tab.lookup("bar").value == null);

    tab.reset(0);
    assert(tab.lookup("foo".ptr, "foo".length) == null);
    //tab.insert("bar");
}

nothrow unittest
{
    StringTable!(void*) tab;
    tab._init(100);

    enum testCount = 2000;

    char[2 * testCount] buf;

    foreach (i; 0 .. testCount)
    {
        buf[i * 2 + 0] = cast(char)(i % 256);
        buf[i * 2 + 1] = cast(char)(i / 256);
        auto toInsert = cast(const(char)[]) buf[i * 2 .. i * 2 + 2];
        tab.insert(toInsert, cast(void*) i);
    }

    foreach (i; 0 .. testCount)
    {
        auto toLookup = cast(const(char)[]) buf[i * 2 .. i * 2 + 2];
        assert(tab.lookup(toLookup).value == cast(void*) i);
    }
}

nothrow unittest
{
    StringTable!(int) tab;
    tab._init(10);
    tab.insert("foo", 4);
    tab.insert("bar", 6);

    static int resultFp = 0;
    int resultDg = 0;
    static bool returnImmediately = false;

    int function(const(StringValue!int)*) nothrow applyFunc = (const(StringValue!int)* s) {
        resultFp += s.value;
        return returnImmediately;
    };

    scope int delegate(const(StringValue!int)*) nothrow applyDeleg = (const(StringValue!int)* s) {
        resultDg += s.value;
        return returnImmediately;
    };

    tab.apply(applyFunc);
    tab.opApply(applyDeleg);

    assert(resultDg == 10);
    assert(resultFp == 10);

    returnImmediately = true;

    tab.apply(applyFunc);
    tab.opApply(applyDeleg);

    // Order of string table iteration is not specified, either foo or bar could
    // have been visited first.
    assert(resultDg == 14 || resultDg == 16);
    assert(resultFp == 14 || resultFp == 16);
}
