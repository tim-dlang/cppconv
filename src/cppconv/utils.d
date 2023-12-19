
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.utils;
import dparsergen.core.grammarinfo;
import std.array;
import std.conv;

static struct IterateCombination
{
    static struct StateEntry
    {
        uint value;
        uint num;
    }

    static struct State
    {
        StateEntry[] entries;
        size_t current;
        size_t lastNotChanged = size_t.max; // how many variables didn't change in last popFront
        size_t numCombinations;
    }

    State* state;
    uint next(uint num)
    in (num)
    {
        if (num == 1)
            return 0;

        if (state.entries.length <= state.current)
        {
            state.entries.length = state.current + 1;
        }
        uint r = state.entries[state.current].value;
        state.entries[state.current].num = num;
        state.current++;
        return r;
    }

    bool prefixDone()
    {
        return state.lastNotChanged != size_t.max && state.current <= state.lastNotChanged;
    }
}

auto iterateCombinations()
{
    static Appender!(IterateCombination.State*[]) stateFreeList;
    static struct R
    {
        IterateCombination.State* state;

        bool empty = false;

        ~this()
        {
            stateFreeList.put(state);
            state = null;
        }

        @disable this(this);

        IterateCombination front()
        {
            return IterateCombination(state);
        }

        void popFront()
        {
            while (state.current)
            {
                state.entries[state.current - 1].value++;
                if (state.entries[state.current - 1].value < state.entries[state.current - 1].num)
                {
                    break;
                }
                else
                {
                    state.current--;
                }
            }
            if (!state.current)
                empty = true;

            foreach (ref x; state.entries[state.current .. $])
                x = IterateCombination.StateEntry(0, 0);

            state.lastNotChanged = state.current - 1;
            state.current = 0;
        }
    }

    IterateCombination.State* state;
    if (stateFreeList.data.length)
    {
        state = stateFreeList.data[$ - 1];
        stateFreeList.shrinkTo(stateFreeList.data.length - 1);
        auto bak = state.entries;
        *state = IterateCombination.State.init;
        state.entries = bak;
    }
    else
    {
        state = new IterateCombination.State;
    }
    return R(state);
}

class SimpleClassAllocator(T)
{
    enum blockSize = 64 * 1024 * 10;
    static if (is(T == class))
        enum classSize = __traits(classInstanceSize, T);
    else
        enum classSize = typeof(*T.init).sizeof;
    static assert(classSize % (void*).sizeof == 0);
    enum classesPerBlock = blockSize / classSize;

    struct ClassData
    {
        void*[classSize / (void*).sizeof] data;
    }

    ClassData[][] usedBlocks;
    static ClassData[][] freeBlocks;
    ClassData[] data;

    ClassData* allocateImpl()
    {
        if (data.length == 0)
        {
            if (freeBlocks.length)
            {
                data = freeBlocks[0];
                usedBlocks ~= data;
                freeBlocks = freeBlocks[1 .. $];
            }
            else
            {
                data = new ClassData[classesPerBlock];
                usedBlocks ~= data;
            }
        }
        auto r = &data[0];
        data = data[1 .. $];
        return r;
    }

    T allocate(Args...)(auto ref Args args)
    {
        ClassData* x = allocateImpl();
        static if (is(T == class))
            return emplace!T(cast(T) x.data.ptr, args);
        else
            return emplace!(typeof(*T.init))(cast(T) x.data.ptr, args);
    }

    void clearAll()
    {
        foreach (block; usedBlocks)
        {
            import core.stdc.string;

            memset(block.ptr, 0, block.length * typeof(block[0]).sizeof);
        }
        freeBlocks ~= usedBlocks;
        usedBlocks = [];
        data = [];
    }
}

enum SimpleArrayAllocatorFlags
{
    none = 0,
    allowReuse = 1,
    noGC = 2
}

struct SimpleArrayAllocator2(T, SimpleArrayAllocatorFlags flags = SimpleArrayAllocatorFlags.none,
        size_t blockSize = 64 * 1024 * 10 - 32)
{
    import std.traits;

    enum classSize = T.sizeof;
    enum classesPerBlock = blockSize / classSize;

    private Unqual!T[] data;
    private Unqual!T[][] usedData;
    static if (flags & SimpleArrayAllocatorFlags.allowReuse)
        private size_t usedBlocks;

    void nextBlock()
    {
        static if (flags & SimpleArrayAllocatorFlags.allowReuse)
        {
            if (usedBlocks < usedData.length)
            {
                data = usedData[usedBlocks];
                usedBlocks++;
                return;
            }
            assert(usedBlocks == usedData.length);
        }
        static if (flags & SimpleArrayAllocatorFlags.noGC)
        {
            import core.stdc.stdlib;

            data = (cast(Unqual!T*) calloc(classesPerBlock, classSize))[0 .. classesPerBlock];
        }
        else
            data = new Unqual!T[classesPerBlock];
        usedData ~= data;
        static if (flags & SimpleArrayAllocatorFlags.allowReuse)
            usedBlocks++;
    }

    T[] allocate(U)(U[] x) if (is(Unqual!T == Unqual!U))
    {
        if (data.length < x.length)
        {
            if ((data.length < 100 || data.length < classesPerBlock / 2)
                    && x.length <= classesPerBlock)
            {
                nextBlock();
            }
            else
                return x.dup;
        }
        auto r = data[0 .. x.length];
        data = data[x.length .. $];
        r[] = x[];
        return (cast(T*) r.ptr)[0 .. r.length];
    }

    T[] allocateOne(T x)
    {
        if (data.length == 0)
        {
            nextBlock();
        }
        auto r = data[0 .. 1];
        emplace!(Unqual!T)(&r[0], cast() x);
        data = data[1 .. $];
        return (cast(T*) r.ptr)[0 .. 1];
    }

    void append(ref T[] prev, T x)
    {
        size_t num = prev.length + 1;
        if (prev.length > 0 && prev.ptr + prev.length is data.ptr && data.length >= 1)
        {
            data[0] = cast(Unqual!T) x;
            data = data[1 .. $];
            prev = (cast(T*) prev.ptr)[0 .. prev.length + 1];
            return;
        }
        if (data.length < num)
        {
            if ((data.length < 100 || data.length < classesPerBlock / 2) && num <= classesPerBlock)
            {
                nextBlock();
            }
            else
            {
                prev ~= x;
                return;
            }
        }
        auto r = data[0 .. num];
        data = data[num .. $];
        r[0 .. prev.length] = cast(Unqual!T[]) prev;
        r[prev.length] = cast(Unqual!T) x;
        prev = (cast(T*) r.ptr)[0 .. num];
    }

    void append(ref T[] prev, T[] x)
    {
        if (x.length == 0)
            return;
        size_t num = prev.length + x.length;
        if (prev.length > 0 && prev.ptr + prev.length is data.ptr && data.length >= x.length)
        {
            data[0 .. x.length] = cast(Unqual!T[]) x;
            data = data[x.length .. $];
            prev = (cast(T*) prev.ptr)[0 .. prev.length + x.length];
            return;
        }
        if (data.length < num)
        {
            if ((data.length < 100 || data.length < classesPerBlock / 2) && num <= classesPerBlock)
            {
                nextBlock();
            }
            else
            {
                prev ~= x;
                return;
            }
        }
        auto r = data[0 .. num];
        data = data[num .. $];
        r[0 .. prev.length] = cast(Unqual!T[]) prev;
        r[prev.length .. num] = cast(Unqual!T[]) x;
        prev = (cast(T*) r.ptr)[0 .. num];
    }
}

immutable(GrammarInfo)* getDummyGrammarInfo(ushort start = 30000)(string name)
{
    static immutable(GrammarInfo)*[string] infos;
    if (name in infos)
        return infos[name];

    SymbolID nonterminalID = cast(SymbolID)(start + infos.length * 2);
    SymbolID productionID = cast(SymbolID)(start + infos.length * 2 + 1);

    immutable allNonterminals = [
        immutable(Nonterminal)(name, NonterminalFlags.nonterminal, [], [nonterminalID]),
    ];
    immutable allProductions = [
        immutable(Production)(immutable(NonterminalID)(nonterminalID), [], [], [], false, false),
    ];

    auto info = new immutable(GrammarInfo)(start, nonterminalID, productionID,
            [], allNonterminals, allProductions);

    infos[name] = info;
    return info;
}

struct ArrayL(T)
{
    struct Data
    {
        union
        {
            size_t length;
            Data* nextPtr;
        }
    }

    static assert(T.alignof <= Data.sizeof);

    Data* data;

    @disable this(this);

    ~this()
    {
        freeData(data);
        data = null;
    }

    T[] toSlice()
    {
        if (data is null)
            return [];
        return (cast(T*)(data + 1))[0 .. data.length];
    }

    T[] opIndex()
    {
        if (data is null)
            return [];
        return (cast(T*)(data + 1))[0 .. data.length];
    }

    size_t length()
    {
        if (data is null)
            return 0;
        return data.length;
    }

    void length(size_t l)
    {
        if (l == 0)
        {
            freeData(data);
            data = null;
            return;
        }
        size_t oldLength = length;
        Data** currentFreeList;
        size_t currentCapacity;
        getFreeList(oldLength, currentFreeList, currentCapacity);
        Data** nextFreeList;
        size_t nextCapacity;
        getFreeList(l, nextFreeList, nextCapacity);
        if (currentCapacity == nextCapacity)
        {
            if (l)
                data.length = l;
            return;
        }
        Data* nextData = allocate(l);
        assert(nextData.length == l);
        T[] nextSlice = (cast(T*)(nextData + 1))[0 .. nextData.length];
        size_t commonLength = oldLength;
        if (l < commonLength)
            commonLength = l;
        nextSlice[0 .. commonLength] = toSlice()[0 .. commonLength];
        freeData(data);
        data = nextData;
    }

    void opOpAssign(string op)(T x) if (op == "~")
    {
        length = length + 1;
        toSlice[$ - 1] = x;
    }

    void opIndexAssign(T x, size_t i)
    {
        toSlice[i] = x;
    }

    ref T opIndex(size_t i)
    {
        return toSlice[i];
    }

    static Data*[8] freeListSmall;
    static Data*[16] freeListLarge;
    static void getFreeList(size_t length, ref Data** freeList, ref size_t capacity)
    {
        if (length == 0)
        {
            freeList = null;
            capacity = 0;
            return;
        }
        if (length <= 8)
        {
            freeList = &freeListSmall[length - 1];
            capacity = length;
            return;
        }
        foreach (i; 0 .. freeListLarge.length)
        {
            capacity = 16 << i;
            if (length <= capacity)
            {
                freeList = &freeListLarge[i];
                return;
            }
        }
        assert(false);
    }

    static Data* allocate(size_t length)
    {
        if (length == 0)
            return null;
        Data** freeList;
        size_t capacity;
        getFreeList(length, freeList, capacity);

        if (!*freeList)
        {
            size_t arraySize = Data.sizeof + capacity * T.sizeof;
            size_t numArrays = 64 * 1024 / arraySize;
            if (numArrays < 1)
                numArrays = 1;
            import core.memory;
            import core.stdc.stdlib;

            ubyte* block = cast(ubyte*) calloc(arraySize, numArrays);
            GC.addRange(block, arraySize * numArrays);
            foreach (i; 0 .. numArrays)
            {
                Data* data = cast(Data*)(block + i * arraySize);
                data.nextPtr = *freeList;
                *freeList = data;
            }
        }

        Data* data = *freeList;
        *freeList = data.nextPtr;
        data.length = length;
        return data;
    }

    static void freeData(Data* data)
    {
        if (data is null)
            return;

        Data** freeList;
        size_t capacity;
        getFreeList(data.length, freeList, capacity);

        T[] slice = (cast(T*)(data + 1))[0 .. data.length];
        slice[] = T.init;

        data.nextPtr = *freeList;
        *freeList = data;
    }
}

struct StackArrayAllocator(T)
{
    static Appender!(T[]) app;
    size_t sizeBegin;
    @disable this();
    this(int dummy)
    {
        sizeBegin = app.data.length;
    }

    ~this()
    {
        app.shrinkTo(sizeBegin);
    }

    T[] data()
    {
        return app.data[sizeBegin .. $];
    }

    void put(T x)
    {
        app.put(x);
    }

    T[] getN(size_t n)
    {
        foreach (i; 0 .. n)
            put(T.init);
        return data[$ - n .. $];
    }
}

StackArrayAllocator!T stackArrayAllocator(T)()
{
    return StackArrayAllocator!T(0);
}

size_t interpolationSearch(string access, string op, T, T2)(T[] data, T2 value)
{
    size_t low = 0;
    size_t high = data.length;
    while (low < high)
    {
        size_t mid = (low + high) / 2;
        mixin("auto x = data[mid]" ~ access ~ ";");
        if (mixin("x " ~ op ~ " value"))
            low = mid + 1;
        else
            high = mid;
    }
    return low;
}
