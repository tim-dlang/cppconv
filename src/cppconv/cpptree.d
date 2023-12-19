
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.cpptree;
import cppconv.locationstack;
import cppconv.stringtable;
import cppconv.utils;
import dparsergen.core.grammarinfo;
import dparsergen.core.nodetype;
import dparsergen.core.nonterminalunion;
import dparsergen.core.parsestackelem;
import dparsergen.core.utils;
import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.typecons;

alias Location = cppconv.locationstack.LocationX;

struct CppParseTreeStruct
{
    alias Location = cppconv.locationstack.LocationX;
    alias LocationRangeImpl = LocationRangeXW;
    alias LocationRange = LocationRangeImpl!Location;
    alias LocationDiff = typeof(Location.init - Location.init);
    union
    {
        string content_;
        CppParseTree[] childs_;
    }

    LocationRange location;
    immutable(GrammarInfo)* grammarInfo;
    ProductionID productionID;
    SymbolID nonterminalID;
    NodeType nodeType;

    this(string name, SymbolID nonterminalID, ProductionID productionID,
            NodeType nodeType, CppParseTree[] childs = [])
    {
        this.nonterminalID = nonterminalID;
        this.nodeType = nodeType;
        if (nodeType == NodeType.token)
            this.content_ = name;
        else
            this.childs_ = childs;
        this.productionID = productionID;
    }
}

static assert(CppParseTreeStruct.sizeof == 64);

struct CppParseTree
{
    alias Location = cppconv.locationstack.LocationX;
    alias LocationRangeImpl = LocationRangeXW;
    alias LocationRange = LocationRangeImpl!Location;
    alias LocationDiff = typeof(Location.init - Location.init);

    CppParseTreeStruct* this_;

    this(inout(CppParseTreeStruct)* this_) inout
    {
        this.this_ = this_;
    }

    this(string name, SymbolID nonterminalID, ProductionID productionID, NodeType nodeType,
            CppParseTree[] childs = [], SimpleClassAllocator!(CppParseTreeStruct*) allocator = null)
    {
        if (allocator is null)
            this_ = new CppParseTreeStruct(name, nonterminalID, productionID, nodeType, childs);
        else
            this_ = allocator.allocate(name, nonterminalID, productionID, nodeType, childs);
    }

    bool isValid() const
    {
        return this_ !is null;
    }

    auto grammarInfo() const
    {
        return this_.grammarInfo;
    }

    void grammarInfo(immutable(GrammarInfo)* g)
    {
        this_.grammarInfo = g;
    }

    ProductionID productionID() const
    {
        return this_.productionID;
    }

    SymbolID nonterminalID() const
    {
        return this_.nonterminalID;
    }

    LocationRange location() const
    {
        return this_.location;
    }

    ref LocationRange location()
    {
        return this_.location;
    }

    string name(string filename = __FILE__, size_t line = __LINE__) const
    in
    {
        assert(nodeType != NodeType.token, text(filename, ":", line));
    }
    do
    {
        if (this_.grammarInfo is null)
            return (nodeType == NodeType.array) ? "[]" : "?";
        return grammarInfo
            .allNonterminals[this_.nonterminalID - this_.grammarInfo.startNonterminalID].name;
    }

    string content(string filename = __FILE__, size_t line = __LINE__) const
    in
    {
        assert(nodeType == NodeType.token, text(filename, ":", line));
    }
    do
    {
        return this_.content_;
    }

    string nameOrContent() const
    {
        if (isToken)
            return content;
        else
            return name;
    }

    inout(CppParseTree[]) childs() inout
    {
        if (this_.nodeType != NodeType.token)
        {
            return this_.childs_;
        }
        return [];
    }

    static foreach (field; ["startFromParent", "inputLength", "start", "end"])
    {
        static if (__traits(hasMember, LocationRange, field))
        {
            mixin("typeof((){LocationRange x; return x." ~ field ~ ";}()) "
                    ~ field ~ "() const {" ~ "return this_.location." ~ field ~ ";}");

            mixin("static if (__traits(compiles, (){LocationRange x; x." ~ field ~ " = x." ~ field ~ ";}))" ~ "void "
                    ~ field ~ "(typeof((){LocationRange x; return x." ~ field
                    ~ ";}()) n){" ~ "this_.location." ~ field ~ " = n;}");
        }
    }

    static if (__traits(hasMember, LocationRange, "setStartEnd"))
    {
        final void setStartEnd(typeof(() { LocationRange x; return x.start; }()) start, typeof(() {
                LocationRange x;
                return x.end;
            }()) end)
        {
            this_.location.setStartEnd(start, end);
        }
    }

    NodeType nodeType() const
    {
        return this_.nodeType;
    }

    string toString() const
    {
        return treeToString(this);
    }

    bool isToken() const
    {
        return nodeType == NodeType.token;
    }

    bool hasChildWithName(string name)
    {
        assert(name.length);
        if (nodeType == NodeType.token)
            return false;
        assert(nodeType == NodeType.nonterminal);
        assert(grammarInfo !is null);

        immutable(SymbolInstance)[] symbols = grammarInfo
            .allProductions[this_.productionID - grammarInfo.startProductionID].symbols;
        while (symbols.length && symbols[$ - 1].dropNode)
            symbols = symbols[0 .. $ - 1];
        assert(symbols.length == this_.childs_.length);

        foreach (i, ref symbol; symbols)
        {
            if (symbol.symbolInstanceName == name)
            {
                return true;
            }
        }

        return false;
    }

    CppParseTree childByName(string name)
    {
        assert(name.length);
        assert(nodeType == NodeType.nonterminal);
        assert(this_.grammarInfo !is null);

        immutable(SymbolInstance)[] symbols = this_.grammarInfo
            .allProductions[this_.productionID - this_.grammarInfo.startProductionID].symbols;
        while (symbols.length && symbols[$ - 1].dropNode)
            symbols = symbols[0 .. $ - 1];
        assert(symbols.length == this_.childs_.length);

        foreach (i, ref symbol; symbols)
        {
            if (symbol.symbolInstanceName == name)
            {
                return this_.childs_[i];
            }
        }

        assert(false);
    }

    string childName(size_t i)
    {
        assert(nodeType == NodeType.nonterminal);
        assert(this_.grammarInfo !is null);

        immutable(SymbolInstance)[] symbols = this_.grammarInfo
            .allProductions[this_.productionID - this_.grammarInfo.startProductionID].symbols;
        while (symbols.length && symbols[$ - 1].dropNode)
            symbols = symbols[0 .. $ - 1];
        assert(symbols.length == this_.childs_.length);

        return symbols[i].symbolInstanceName;
    }

    string childNonterminalName(size_t i)
    {
        assert(nodeType == NodeType.nonterminal);
        assert(this_.grammarInfo !is null);

        immutable(SymbolInstance)[] symbols = this_.grammarInfo
            .allProductions[this_.productionID - this_.grammarInfo.startProductionID].symbols;
        while (symbols.length && symbols[$ - 1].dropNode)
            symbols = symbols[0 .. $ - 1];
        assert(symbols.length == this_.childs_.length);

        if (symbols[i].isToken)
            return "";
        else
            return this_.grammarInfo.allNonterminals[symbols[i].toNonterminalID.id /* - this_.grammarInfo.startNonterminalID*/ ]
                .name;
    }

    static void iterateChilds(T2, V)(T2 tree, V visitor) // if (is(Unqual!T2 == CppParseTree))
    {
        foreach (ref c; tree.childs)
        {
            if (!visitor.visit(c))
                return;
        }
    }
}

bool isValid(const CppParseTreeStruct* t)
{
    return t !is null;
}

struct CppParseTreeArray
{
    alias Location = cppconv.locationstack.LocationX;
    alias LocationRangeImpl = LocationRangeXW;
    alias LocationDiff = typeof(Location.init - Location.init);
    CppParseTree[] trees;
    Location end;
    alias trees this;
    enum isValid = true;
    enum specialArrayType = true;
}

/**
Convert tree to string.
*/
void treeToString(const CppParseTree tree, ref Appender!string app)
{
    if (!tree.isValid)
    {
        app.put("null");
        return;
    }

    if (tree.nodeType == NodeType.token)
    {
        app.put("\"");
        foreach (dchar c; tree.content)
            app.put(escapeChar(c, false));
        app.put("\"");
    }
    else if (tree.nodeType == NodeType.array)
    {
        foreach (i, c; tree.childs)
        {
            if (i)
                app.put(", ");
            treeToString(c, app);
        }
    }
    else if (tree.nodeType == NodeType.nonterminal || tree.nodeType == NodeType.merged)
    {
        if (tree.nodeType == NodeType.merged)
            app.put("Merged:");
        app.put(tree.name);
        app.put("(");
        foreach (i, c; tree.childs)
        {
            if (c.isValid && c.nodeType == NodeType.array && c.childs.length == 0)
                continue;
            if (!app.data.endsWith(", ") && !app.data.endsWith("("))
                app.put(", ");
            treeToString(c, app);
        }
        /*if (app.data.endsWith(", "))
            app.shrinkTo(app.data.length - 2);*/
        app.put(")");
    }
    else
        assert(false);
}

/// ditto
string treeToString(const CppParseTree tree)
{
    Appender!string app;
    treeToString(tree, app);
    return app.data;
}

struct CppParseTreeCreator(alias GrammarModule)
{
    alias Location = cppconv.locationstack.LocationX;
    alias LocationRangeImpl = LocationRangeXW;
    alias LocationDiff = typeof(Location.init - Location.init);
    alias allTokens = GrammarModule.allTokens;
    alias allNonterminals = GrammarModule.allNonterminals;
    alias allProductions = GrammarModule.allProductions;
    alias Type = CppParseTree;
    alias NonterminalArray = CppParseTreeArray;
    enum startNonterminalID = GrammarModule.startNonterminalID;
    enum endNonterminalID = GrammarModule.endNonterminalID;
    enum startProductionID = GrammarModule.startProductionID;
    enum endProductionID = GrammarModule.endProductionID;

    SimpleClassAllocator!(CppParseTreeStruct*) allocator;
    StringTable!(ubyte[0])* stringPool;

    static SymbolID nonterminalForName(string name)
    {
        foreach (i; 0 .. allNonterminals.length)
        {
            if (allNonterminals[i].name == name)
                return cast(SymbolID) i;
        }
        return SymbolID.max;
    }

    template NonterminalType(SymbolID nonterminalID)
    {
        //static assert(!allNonterminals[nonterminalID - startNonterminalID].annotations.contains!"String"());
        static if (allNonterminals[nonterminalID - startNonterminalID]
                .flags & NonterminalFlags.array)
            alias NonterminalType = CppParseTreeArray;
        else static if (
            allNonterminals[nonterminalID - startNonterminalID].flags & NonterminalFlags.string)
            alias NonterminalType = string;
        else
            alias NonterminalType = CppParseTree;
    }

    template canMerge(SymbolID nonterminalID)
    {
        enum canMerge = is(NonterminalType!nonterminalID == CppParseTree)
            || is(NonterminalType!nonterminalID == CppParseTreeArray);
    }

    alias NonterminalUnion = GenericNonterminalUnion!(CppParseTreeCreator).Union;
    alias NonterminalUnionAny = GenericNonterminalUnion!(CppParseTreeCreator).Union!(
            SymbolID.max, size_t.max);
    template createParseTree(SymbolID productionID)
    {
        NonterminalType!(allProductions[productionID - startProductionID].nonterminalID.id) createParseTree(
                T...)(Location firstParamStart, Location lastParamEnd, T params)
                if (allProductions[productionID - startProductionID].symbols.length > 0)
        {
            enum nonterminalID = allProductions[productionID - startProductionID].nonterminalID.id;
            enum nonterminalName = allNonterminals[nonterminalID - startNonterminalID].name;
            enum nonterminalFlags = allNonterminals[nonterminalID - startNonterminalID].flags;
            assert(firstParamStart <= lastParamEnd);

            size_t numChilds;
            CppParseTree[] childs;
            foreach (i, p; params)
            {
                static if (is(typeof(p.val) : CppParseTree))
                {
                    numChilds++;
                }
                else static if (is(typeof(p.val) : CppParseTreeArray))
                {
                    static if (nonterminalFlags & NonterminalFlags.array)
                    {
                        if (i == 0)
                            childs = p.val.trees;
                        numChilds += p.val.trees.length;
                    }
                    else
                    {
                        numChilds++;
                    }
                }
                else
                {
                    numChilds++;
                }
            }
            childs.reserve(numChilds);
            foreach (i, p; params)
            {
                static if (is(typeof(p.val) : CppParseTree))
                {
                    childs ~= p.val;
                }
                else static if (is(typeof(p.val) : CppParseTreeArray))
                {
                    static if (nonterminalFlags & NonterminalFlags.array)
                    {
                        if (i != 0)
                            childs ~= p.val.trees;
                    }
                    else
                    {
                        childs ~= CppParseTree("[]", SymbolID.max,
                                ProductionID.max, NodeType.array, p.val.trees, allocator);
                        childs[$ - 1].setStartEnd(p.start, p.end);
                    }
                }
                else
                {
                    string t = stringPool.update(p.val).toString();
                    childs ~= CppParseTree(t, SymbolID.max, ProductionID.max,
                            NodeType.token, [], allocator);
                    if (t == "")
                        childs[$ - 1].setStartEnd(Location.invalid, Location.invalid);
                    else
                        childs[$ - 1].setStartEnd(p.start, p.end);
                }
            }

            static if (nonterminalFlags & NonterminalFlags.array)
            {
                return CppParseTreeArray(childs, lastParamEnd);
            }
            else static if (nonterminalFlags & NonterminalFlags.string)
            {
                string r;
                foreach (c; childs)
                    r ~= c.content;
                return r;
            }
            else
            {
                auto r = CppParseTree(nonterminalName, nonterminalID,
                        productionID, NodeType.nonterminal, childs, allocator);
                r.setStartEnd(firstParamStart, lastParamEnd);
                r.grammarInfo = &GrammarModule.grammarInfo;
                return r;
            }
        }

        NonterminalType!(allProductions[productionID - startProductionID].nonterminalID.id) createParseTree()(
                Location firstParamStart, Location lastParamEnd)
                if (allProductions[productionID - startProductionID].symbols.length == 0)
        {
            static if (is(typeof(return) : CppParseTreeArray))
            {
                return CppParseTreeArray([], Location.invalid);
            }
            else
                return null;
        }
    }

    void adjustStart(T)(T result, Location start)
    {
        static if (!is(typeof(result.start)))
            if (result.validTreeNode)
                result.startFromParent = start - Location();
    }

    CppParseTree mergeParseTreesImpl(Location firstParamStart, Location lastParamEnd,
            ParseStackElem!(Location, CppParseTree)[] trees, string mergeInfo = "")
    {
        CppParseTree[] childs;
        foreach (i, p; trees)
        {
            childs ~= p.val;
        }

        string name = mergeInfo;
        if (name.length == 0)
            name = "Merged" /*~nonterminalName*/ ;
        auto grammarInfo = getDummyGrammarInfo(name);
        auto r = CppParseTree(name, grammarInfo.startNonterminalID,
                grammarInfo.startProductionID, NodeType.merged, childs, allocator);
        r.grammarInfo = grammarInfo;
        r.setStartEnd(firstParamStart, lastParamEnd);
        return r;
    }

    CppParseTreeArray mergeParseTreesImplArray(Location firstParamStart, Location lastParamEnd,
            ParseStackElem!(Location, CppParseTreeArray)[] trees, string mergeInfo = "")
    {
        size_t commonPrefix;
        outer: while (true)
        {
            foreach (p; trees)
            {
                if (p.val.trees.length <= commonPrefix)
                    break outer;
            }
            foreach (i, p; trees[0 .. $ - 1])
            {
                if (trees[i].val.trees[commonPrefix]!is trees[i + 1].val.trees[commonPrefix])
                    break outer;
            }
            commonPrefix++;
        }

        CppParseTree[] childs;
        foreach (i, p; trees)
        {
            childs ~= CppParseTree("[]", SymbolID.max, ProductionID.max,
                    NodeType.array, p.val.trees[commonPrefix .. $], allocator);
            childs[$ - 1].setStartEnd(p.start, p.end);
        }

        string name = mergeInfo;
        if (name.length == 0)
            name = "Merged" /*~nonterminalName*/ ;
        auto grammarInfo = getDummyGrammarInfo(name);
        auto r = CppParseTree(name, grammarInfo.startNonterminalID,
                grammarInfo.startProductionID, NodeType.merged, childs, allocator);
        r.grammarInfo = grammarInfo;
        r.setStartEnd(firstParamStart, lastParamEnd);
        return CppParseTreeArray(trees[0].val.trees[0 .. commonPrefix] ~ [r], lastParamEnd);
    }

    template mergeParseTrees(SymbolID nonterminalID)
    {
        NonterminalType!(nonterminalID) mergeParseTrees(Location firstParamStart, Location lastParamEnd,
                ParseStackElem!(Location, NonterminalType!nonterminalID)[] trees,
                string mergeInfo = "")
        {
            if (mergeInfo.length == 0)
            {
                string[] childNames;
                foreach (c; trees)
                {
                    string name;
                    static if (is(NonterminalType!nonterminalID == CppParseTreeArray))
                    {
                        foreach (x; c.val.trees)
                        {
                            if (name.length)
                                name ~= " ";
                            if (!x.isValid)
                                name ~= "null";
                            else
                                name ~= x.nameOrContent;
                        }
                    }
                    else
                    {
                        if (!c.val.isValid)
                            name = "null";
                        else
                            name = c.val.name;
                    }
                    childNames ~= name;
                }
                sort(childNames);
                mergeInfo = "Merged:" ~ allNonterminals[nonterminalID - startNonterminalID].name
                    ~ "(" ~ childNames.join(" | ") ~ ")";
            }
            static if (is(NonterminalType!nonterminalID == CppParseTreeArray))
                return mergeParseTreesImplArray(firstParamStart, lastParamEnd, trees, mergeInfo);
            else
                return mergeParseTreesImpl(firstParamStart, lastParamEnd, trees, mergeInfo);
        }
    }
}
