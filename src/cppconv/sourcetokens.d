
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.sourcetokens;
import cppconv.common;
import cppconv.conditiontree;
import cppconv.configreader;
import cppconv.cppdeclaration;
import cppconv.cppsemantic;
import cppconv.cpptype;
import cppconv.declarationpattern;
import cppconv.filecache;
import cppconv.logic;
import cppconv.macrodeclaration;
import cppconv.mergedfile;
import cppconv.preproc;
import cppconv.preprocparserwrapper;
import cppconv.runcppcommon;
import cppconv.treemerging;
import cppconv.utils;
import dparsergen.core.nodetype;
import dparsergen.core.utils;
import cppconv.codewriter;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.typecons;

alias nonterminalIDFor = ParserWrapper.nonterminalIDFor;
alias nonterminalIDAmong = ParserWrapper.nonterminalIDAmong;

struct SourceToken
{
    Tree token;
    immutable(Formula)* condition;
    bool isWhitespace;
    bool isIncludeGuard;
}

struct PPConditionalInfo
{
    Tree[] directives;
}

struct DeclarationTokens
{
    SourceToken[] tokensBefore;
    SourceToken[] tokensInside;
    SourceToken[] tokensAfter;
}

class SourceTokenManager
{
    LogicSystem logicSystem;
    LocationContextMap locationContextMap;
    MergedFile*[RealFilename] mergedFileByName;

    SourceToken[][RealFilename] sourceTokens;
    SourceToken[][RealFilename] sourceTokensMacros;

    PPConditionalInfo*[Tree] ppConditionalInfo;

    MacroDeclaration[Tuple!(string, LocationRangeX)] macroDeclarations;

    Appender!(Declaration[]) commentDeclarations;

    SimpleArrayAllocator2!(SourceToken, SimpleArrayAllocatorFlags.noGC, 10 * 1024 * 1024 * 1024 - 32) sourceTokenAllocator;
    SimpleArrayAllocator2!(SourceToken, SimpleArrayAllocatorFlags.noGC, 10 * 1024 * 1024 * 1024 - 32) sourceTokenAllocatorMacros;

    LocationX locDone;
    immutable(LocationContext)* currentMacroLocation;
    Appender!(SourceToken[][]) tokensLeft;
    immutable(LocationContext)* tokensContext;
    bool inInterpolateMixin;

    DeclarationTokens[Declaration] declarationTokens_;
    DeclarationTokens* declarationTokens(Declaration d)
    {
        auto x = d in declarationTokens_;
        if (x)
            return x;
        declarationTokens_[d] = DeclarationTokens();
        return d in declarationTokens_;
    }
}

int filenameOrder(string filename)
{
    if (filename.endsWith(".h") || filename.endsWith(".hpp"))
        return 1;
    if (filename.endsWith(".c") || filename.endsWith(".cpp"))
        return 3;
    return 2; // No extension is used for C++ headers in STL.
}

int cmpFilename(string name1, string name2)
{
    int order1 = filenameOrder(name1);
    int order2 = filenameOrder(name2);
    if (order1 < order2)
        return -1;
    if (order1 > order2)
        return 1;
    if (name1 < name2)
        return -1;
    if (name1 > name2)
        return 1;
    return 0;
}

bool cmpDeclarationLoc(Declaration a, Declaration b, Semantic semantic)
{
    LocationX locA;
    if (!a.tree.isValid)
        locA = a.location.end;
    else
        locA = a.tree.location.end;
    LocationX locB;
    if (!b.tree.isValid)
        locB = b.location.end;
    else
        locB = b.tree.location.end;
    auto pa = getLocationFilePrefix(locA);
    auto pb = getLocationFilePrefix(locB);

    if (pa is null && pb is null)
        return false;
    if (pa is null)
        return true;
    if (pb is null)
        return false;
    if (pa !is null && pb !is null)
    {
        int c = cmpFilename(pa.filename, pb.filename);
        if (c != 0)
            return c < 0;
    }

    LocationX la = removeLocationFilePrefix(locA, semantic.locationContextMap);
    LocationX lb = removeLocationFilePrefix(locB, semantic.locationContextMap);
    int c = la.opCmp2(lb, true);
    if (c != 0)
        return c < 0;

    c = a.location.end.opCmp(b.location.end);
    if (c != 0)
        return c < 0;

    if (a is null && b !is null)
        return true;
    if (a !is null && b is null)
        return false;

    c = cmpFilename(a.location.context.rootFilename, b.location.context.rootFilename);
    if (c != 0)
        return c < 0;

    if (a !is null && b !is null)
    {
        c = a.condition.opCmp(*b.condition);
        if (c != 0)
            return c < 0;
    }

    if (a.name != b.name)
        return a.name < b.name;

    return false;
}

bool isSpaceToken(string t)
{
    if (t.length == 0)
        return true;
    if (t[0].among(' ', '\t', '\n', '\r'))
        return true;
    if (t.length >= 2 && t[0] == '/' && t[1].among('*', '/', '+'))
        return true;
    return false;
}

Tree[] findParentTemplateDeclarations(Tree tree, Semantic semantic)
{
    Tree[] templateDeclarations;
    size_t indexInParent;
    for (Tree t = getRealParent(tree, semantic, &indexInParent); t.isValid; t = getRealParent(t, semantic, &indexInParent))
    {
        if (t.nonterminalID == nonterminalIDFor!"TemplateDeclaration"
                && indexInParent == t.childs.length - 1)
            templateDeclarations ~= t;
        else if (t.nonterminalID.nonterminalIDAmong!("DeclSpecifierSeq")
                || t.name.canFind("Declaration"))
        {
        }
        else
            break;
    }
    return templateDeclarations;
}

SourceToken[] collectTokens(SourceTokenManager sourceTokenManager, LocationX loc,
        bool isEnd = false, string filename = __FILE__, size_t line = __LINE__)
{
    sourceTokenManager.currentMacroLocation = null;
    while (loc.context !is null && (sourceTokenManager.tokensContext is null
            || loc.context.contextDepth > sourceTokenManager.tokensContext.contextDepth)
            && loc.context.name.length)
    {
        sourceTokenManager.currentMacroLocation = loc.context;
        loc = loc.context.parentLocation.end;
    }
    if (!isEnd && loc.context is null)
        return [];

    if (!isEnd && sourceTokenManager.tokensContext !is null)
        assert(loc.context.contextDepth == sourceTokenManager.tokensContext.contextDepth,
                text(loc.context.contextDepth, " ", sourceTokenManager.tokensContext.contextDepth));

    if (!isEnd)
        assert(!loc.context.isPreprocLocation);

    LocationX commonContext1 = sourceTokenManager.locDone;
    LocationX commonContext2 = loc;
    findCommonLocationContext(commonContext1, commonContext2);

    if (!isEnd && sourceTokenManager.locDone.context !is null)
    {
        if (commonContext1.context is null)
            return [];
        assert(commonContext1.context !is null, text(locationStr(sourceTokenManager.locDone),
                " ", locationStr(loc), "  ", filename, ":", line));
        //assert(loc >= sourceTokenManager.locDone, text(locationStr(sourceTokenManager.locDone), " ", locationStr(loc), "  ", file, ":", line));
    }

    static Appender!(SourceToken[]) r;
    static size_t recursionCounter;
    if (recursionCounter == 0)
        r.clear();
    recursionCounter++;
    scope (exit)
        recursionCounter--;

    while (sourceTokenManager.locDone.context !is commonContext1.context)
    {
        assert(sourceTokenManager.tokensLeft.data.length == sourceTokenManager.locDone.context.contextDepth);
        r.put(sourceTokenManager.tokensLeft.data[$ - 1]);
        sourceTokenManager.locDone = sourceTokenManager.locDone.context.parentLocation.start;
        sourceTokenManager.tokensLeft.shrinkTo(sourceTokenManager.tokensLeft.data.length - 1);
    }

    if (isEnd)
        return r.data;

    if (loc.context !is commonContext1.context)
    {
        (sourceTokenManager.collectTokens(loc.context.parentLocation.start));
        assert(sourceTokenManager.tokensLeft.data.length + 1 == loc.context.contextDepth);

        if (RealFilename(loc.context.filename) in sourceTokenManager.sourceTokens)
            sourceTokenManager.tokensLeft.put(
                    sourceTokenManager.sourceTokens[RealFilename(loc.context.filename)]);
        else
            sourceTokenManager.tokensLeft.put(SourceToken[].init);

        assert(sourceTokenManager.tokensLeft.data.length == loc.context.contextDepth);
    }

    assert(sourceTokenManager.tokensLeft.data.length == loc.context.contextDepth,
            text(sourceTokenManager.tokensLeft.data.length, " ",
                loc.context.contextDepth, " ", locationStr(loc)));

    size_t numBefore;
    while (numBefore < sourceTokenManager.tokensLeft.data[$ - 1].length
            && sourceTokenManager.tokensLeft.data[$ - 1][numBefore].token.start.loc < loc.loc)
        numBefore++;

    size_t numUsed = numBefore;
    r.put(sourceTokenManager.tokensLeft.data[$ - 1][0 .. numUsed]);
    sourceTokenManager.tokensLeft.data[$ - 1] = sourceTokenManager.tokensLeft
        .data[$ - 1][numUsed .. $];
    sourceTokenManager.locDone = loc;
    return r.data;
}

SourceToken[] collectTokensUntilLineEnd(SourceTokenManager sourceTokenManager, LocationX loc,
        immutable(Formula)* condition, int onlyFullWS = 1,
        string filename = __FILE__, size_t line = __LINE__)
{
    sourceTokenManager.currentMacroLocation = null;
    while (loc.context !is null && (sourceTokenManager.tokensContext is null
            || loc.context.contextDepth > sourceTokenManager.tokensContext.contextDepth)
            && loc.context.name.length)
    {
        sourceTokenManager.currentMacroLocation = loc.context;
        loc = loc.context.parentLocation.end;
    }

    if (sourceTokenManager.tokensContext !is null)
        assert(loc.context.contextDepth == sourceTokenManager.tokensContext.contextDepth,
                text(loc.context.contextDepth, " ", sourceTokenManager.tokensContext.contextDepth));

    assert(!loc.context.isPreprocLocation);
    assert(sourceTokenManager.locDone == loc);

    static Appender!(SourceToken[]) r;
    r.clear();

    assert(sourceTokenManager.tokensLeft.data.length == loc.context.contextDepth,
            text(sourceTokenManager.tokensLeft.data.length, " ", loc.context.contextDepth));

    if (loc.offset == 0)
        return r.data;

    size_t numUsed = 0;
    while (numUsed < sourceTokenManager.tokensLeft.data[$ - 1].length)
    {
        if (sourceTokenManager.tokensLeft.data[$ - 1][numUsed].token.location.start.line > loc.line)
            break;
        if (sourceTokenManager.tokensLeft.data[$ - 1][numUsed].token.content.among("\n", "\r\n"))
        {
            numUsed++;
            break;
        }
        if (!sourceTokenManager.tokensLeft.data[$ - 1][numUsed].isWhitespace
                || sourceTokenManager.tokensLeft.data[$ - 1][numUsed].condition !is condition
                || (onlyFullWS >= 2
                    && !(sourceTokenManager.tokensLeft.data[$ - 1][numUsed].token.content.startsWith(" ")
                    || sourceTokenManager.tokensLeft.data[$ - 1][numUsed].token.content.startsWith("\t"))))
        {
            if (onlyFullWS == 1)
                numUsed = 0;
            break;
        }
        numUsed++;
    }
    r.put(sourceTokenManager.tokensLeft.data[$ - 1][0 .. numUsed]);
    sourceTokenManager.tokensLeft.data[$ - 1] = sourceTokenManager.tokensLeft
        .data[$ - 1][numUsed .. $];
    return r.data;
}

void processSource(SourceTokenManager sourceTokenManager, Tree tree,
        ref SourceToken[] sourceTokens, ref SourceToken[] sourceTokensMacros,
        ref LocConditions.Entry[] locEntries,
        PPConditionalInfo* ppConditionalInfo = null, bool includeGuardPossible = false)
{
    if (locEntries.length == 0)
        return;
    void addSourceToken(Tree t, bool isWhitespace, bool inMacro = false,
            bool isIncludeGuard = false, string filename = __FILE__, size_t line = __LINE__)
    {
        if (t.nameOrContent.length)
        {
            while (locEntries.length && locEntries[0].end <= t.start.loc)
                locEntries = locEntries[1 .. $];
            if (locEntries.length == 0)
            {
                writeln("WARNING: source file ", t.start.context.filename, " grew");
                return;
            }
            assert(t.end.loc <= locEntries[0].end,
                    text(t.start.context.filename, " ", locationStr(t.end.loc),
                        " ", locationStr(locEntries[0].end)));
            if (inMacro)
                sourceTokenManager.sourceTokenAllocatorMacros.append(sourceTokensMacros,
                        SourceToken(t, locEntries[0].condition, isWhitespace));
            else
                sourceTokenManager.sourceTokenAllocator.append(sourceTokens,
                        SourceToken(t, locEntries[0].condition, isWhitespace, isIncludeGuard));
        }
    }

    if (tree.nonterminalID == preprocNonterminalIDFor!"TextLine")
    {
        foreach (c; tree.childs[0].childs)
            addSourceToken(c, true);
        foreach (c; tree.childs[1].childs)
        {
            assert(c.nonterminalID == preprocNonterminalIDFor!"Token");
            addSourceToken(c.childs[0], false);
            foreach (c2; c.childs[1].childs)
                addSourceToken(c2, true);
        }
        addSourceToken(tree.childs[2], true);
    }
    else if (tree.nonterminalID == preprocNonterminalIDFor!"EmptyLine")
    {
        if (tree.childs.length >= 2)
            foreach (c; tree.childs[0].childs)
                addSourceToken(c, true);
        addSourceToken(tree.childs[$ - 1], true);
    }
    else if (tree.nonterminalID == preprocNonterminalIDFor!"PreprocessingFile")
    {
        if (includeGuardPossible)
        {
            size_t countCondition;
            size_t countNonEmpty;
            foreach (c; tree.childs[0].childs)
            {
                if (c.name.startsWith("Conditional"))
                    countCondition++;
                else if (c.name != "EmptyLine")
                    countNonEmpty++;
            }
            if (countCondition != 1 || countNonEmpty > 0)
                includeGuardPossible = false;
        }

        foreach (c; tree.childs[0].childs)
            processSource(sourceTokenManager, c, sourceTokens,
                    sourceTokensMacros, locEntries, null, includeGuardPossible);
    }
    else if (tree.name.startsWith("Conditional"))
    {
        if (tree.nonterminalID == preprocNonterminalIDFor!"Conditional")
            ppConditionalInfo = new PPConditionalInfo;

        if (includeGuardPossible && tree.childs[0].nonterminalID == preprocNonterminalIDFor!"PPIfNDef"
                && tree.childs[2].nonterminalID == preprocNonterminalIDFor!"PPEndif")
        {
            string guardDefine = tree.childs[0].childs[$ - 1].childs[0].content;
            Tree guardDefineTree;
            foreach (c; tree.childs[1].childs)
            {
                if (c.nonterminalID == preprocNonterminalIDFor!"EmptyLine")
                    continue;
                else if (c.nameOrContent == "VarDefine"
                        && c.childs[$ - 3].nameOrContent == guardDefine)
                    guardDefineTree = c;
                else
                    break;
            }
            if (guardDefineTree.isValid)
            {
                LocConditions.Entry[] locEntries2 = locEntries;
                while (locEntries2.length && locEntries2[0].end <= tree.childs[0].start.loc)
                    locEntries2 = locEntries2[1 .. $];
                if (locEntries2.length == 0)
                {
                    writeln("WARNING: source file ", tree.childs[0].start.context.filename, " grew");
                    return;
                }
                auto conditionOutside = locEntries2[0].condition;

                while (locEntries2.length && locEntries2[0].end <= guardDefineTree.start.loc)
                    locEntries2 = locEntries2[1 .. $];
                if (locEntries2.length == 0)
                {
                    writeln("WARNING: source file ",
                            guardDefineTree.start.context.filename, " grew");
                    return;
                }
                auto conditionInside = locEntries2[0].condition;
                if (conditionOutside is conditionInside)
                {
                    ppConditionalInfo.directives ~= tree.childs[0];
                    sourceTokenManager.ppConditionalInfo[tree.childs[0]] = ppConditionalInfo;
                    ppConditionalInfo.directives ~= tree.childs[2];
                    sourceTokenManager.ppConditionalInfo[tree.childs[2]] = ppConditionalInfo;

                    addSourceToken(tree.childs[0], false, false, true);
                    Tree[] childs = tree.childs[1].childs;
                    while (childs[$ - 1].nonterminalID == preprocNonterminalIDFor!"EmptyLine"
                            && childs[$ - 1].childs.length == 1)
                        childs = childs[0 .. $ - 1];
                    bool start = true;
                    foreach (c; childs)
                    {
                        if (start && c.nonterminalID == preprocNonterminalIDFor!"EmptyLine"
                                && c.childs.length == 1)
                            continue;
                        else if (c is guardDefineTree)
                            addSourceToken(c, false, false, true);
                        else
                        {
                            start = false;
                            processSource(sourceTokenManager, c, sourceTokens,
                                    sourceTokensMacros, locEntries);
                        }
                    }
                    addSourceToken(tree.childs[2], false, false, true);
                    return;
                }
            }
        }

        processSource(sourceTokenManager, tree.childs[0], sourceTokens,
                sourceTokensMacros, locEntries, ppConditionalInfo);
        foreach (c; tree.childs[1].childs)
            processSource(sourceTokenManager, c, sourceTokens, sourceTokensMacros, locEntries);
        processSource(sourceTokenManager, tree.childs[2], sourceTokens,
                sourceTokensMacros, locEntries, ppConditionalInfo);
    }
    else if (tree.name.startsWith("PPIf") || tree.name.among("PPEndif", "PPElse", "PPElif"))
    {
        ppConditionalInfo.directives ~= tree;
        sourceTokenManager.ppConditionalInfo[tree] = ppConditionalInfo;
        addSourceToken(tree, false);
    }
    else if (tree.name.among("VarDefine", "FuncDefine"))
    {
        addSourceToken(tree, false);
        string macroName = tree.childs[5].content;

        immutable(LocationContext)* locationContext2 = sourceTokenManager.locationContextMap.getLocationContext(
                immutable(LocationContext)(null,
                LocationN.init, LocationN.LocationDiff.init, "", tree.location.context.filename));
        LocationRangeX l = LocationRangeX(LocationX(tree.start.loc,
                locationContext2), tree.inputLength);

        Tuple!(string, LocationRangeX) key = tuple!(string, LocationRangeX)(macroName, l);
        if (key !in sourceTokenManager.macroDeclarations)
        {
            MacroDeclaration macroDeclaration = new MacroDeclaration;
            macroDeclaration.type = DeclarationType.macro_;
            macroDeclaration.name = macroName;
            macroDeclaration.location = l;
            if (RealFilename(l.context.filename) in sourceTokenManager.mergedFileByName
                    && sourceTokenManager.mergedFileByName[RealFilename(
                            l.context.filename)].locConditions.entries.length)
            {
                macroDeclaration.condition = sourceTokenManager.mergedFileByName[RealFilename(
                            l.context.filename)].locConditions.find(l.start.loc, l.end.loc);
            }
            else
            {
                macroDeclaration.condition = sourceTokenManager.logicSystem.false_;
            }
            sourceTokenManager.macroDeclarations[key] = macroDeclaration;

            macroDeclaration.definition = tree;
            sourceTokenManager.declarationTokens(macroDeclaration)
                .tokensInside = [
                    SourceToken(tree, macroDeclaration.condition, false)
            ];
        }
        else
        {
            MacroDeclaration macroDeclaration = sourceTokenManager.macroDeclarations[key];
            macroDeclaration.definition = tree;
        }

        foreach (c; tree.childs[0].childs)
            addSourceToken(c, true, true);
        foreach (c; tree.childs[1].childs)
            addSourceToken(c, false, true); // #
        foreach (c; tree.childs[2].childs)
            addSourceToken(c, true, true);
        foreach (c; tree.childs[3].childs)
            addSourceToken(c, false, true); // define
        foreach (c; tree.childs[4].childs)
            addSourceToken(c, true, true);
        foreach (c; tree.childs[5].childs)
            addSourceToken(c, false, true); // name
        if (tree.nonterminalID == preprocNonterminalIDFor!"FuncDefine")
        {
            foreach (c; tree.childs[6].childs)
                addSourceToken(c, false, true); // (
            foreach (c; tree.childs[7].childs)
                addSourceToken(c, false, true); // FuncParams
            foreach (c; tree.childs[8].childs)
                addSourceToken(c, false, true); // 6
        }
        foreach (c; tree.childs[$ - 2].childs)
            addSourceToken(c, true, true);
        foreach (c; tree.childs[$ - 1].childs)
        {
            if (c.name.among("Token", "TokenInFunc"))
            {
                addSourceToken(c.childs[0], false, true);
                foreach (c2; c.childs[1].childs)
                    addSourceToken(c2, true, true);
            }
            else if (c.nonterminalID == preprocNonterminalIDFor!"ParamExpansion")
            {
                addSourceToken(c.childs[0], false, true);
                foreach (c2; c.childs[1].childs)
                    addSourceToken(c2, true, true);
                addSourceToken(c.childs[2], false, true);
                foreach (c2; c.childs[3].childs)
                    addSourceToken(c2, true, true);
            }
            else
                assert(false, c.name);
        }
    }
    else
        addSourceToken(tree, false);
}

void matchDeclTokens(SourceTokenManager sourceTokenManager, Semantic semantic, MergedFile* mergedFile,
        bool delegate(Declaration) useDeclaration, bool delegate(string filename) includeDeclsForFile)
{
    assert(sourceTokenManager.tokensLeft.data.length == 0);
    void addCommentDecls(SourceToken[] tokens)
    {
        while (tokens.length)
        {
            size_t numCompatible = 1;
            if (tokens[0].token.nodeType != NodeType.token
                    && tokens[0].token.name.among("VarDefine", "FuncDefine"))
            {
                /* They were already put in tokensInside for the declarations by processSource. */
                tokens = tokens[1 .. $];
                continue;
            }
            if (tokens[0].isIncludeGuard)
            {
                tokens = tokens[1 .. $];
                continue;
            }
            if (tokens[0].token.start.context.filename != mergedFile.filename.name)
            {
                tokens = tokens[1 .. $];
                continue;
            }
            if (tokens[0].token.nodeType == NodeType.token)
                while (numCompatible < tokens.length && tokens[numCompatible].token.nodeType == NodeType.token
                        && tokens[numCompatible - 1].token.start.context is tokens[numCompatible].token.start.context
                        && tokens[numCompatible - 1].condition is tokens[numCompatible].condition)
                    numCompatible++;
            auto tokensHere = tokens[0 .. numCompatible];
            tokens = tokens[numCompatible .. $];
            if (includeDeclsForFile(mergedFile.filename.name))
            {
                Declaration decl = new Declaration;
                decl.type = DeclarationType.comment;
                decl.location.setStartEnd(tokensHere[0].token.start, tokensHere[$ - 1].token.end);
                decl.location = LocationRangeX(LocationX(tokensHere[0].token.start.loc,
                        semantic.locationContextMap.getLocationContext(immutable(LocationContext)(null, LocationN(),
                        LocationN.LocationDiff(), "", tokensHere[0].token.start.context.filename))),
                        tokensHere[$ - 1].token.end.loc - tokensHere[0].token.start.loc);
                decl.condition = tokensHere[0].condition;
                auto declarationTokens = sourceTokenManager.declarationTokens(decl);
                declarationTokens.tokensInside = sourceTokenManager.sourceTokenAllocator.allocate(
                        tokensHere);
                sourceTokenManager.commentDeclarations.put(decl);
            }
        }
    }

    void visitTree(Tree tree)
    {
        if (!tree.isValid)
            return;
        auto extraInfo = &semantic.extraInfo(tree);

        if (extraInfo.declarations.length && !(tree.nodeType == NodeType.nonterminal
                && tree.nonterminalID.nonterminalIDAmong!("OriginalNamespaceDefinition", /*"ExtensionNamespaceDefinition"*/ )))
        {
            Declaration[] declarationsSorted;
            foreach (d; extraInfo.declarations)
                if (useDeclaration(d))
                {
                    declarationsSorted ~= d;
                }
            if (declarationsSorted.length == 0)
                return;
            static LocationRangeX getDeclaratorLoc(Declaration d)
            {
                if (d.type == DeclarationType.namespaceBegin)
                {
                    LocationRangeX r;
                    r.setStartEnd(d.declaratorTree.start, d.declaratorTree.childs[$ - 3].end);
                    return r;
                }
                return (!d.declaratorTree.isValid) ? d.location : d.declaratorTree.location;
            }

            declarationsSorted.sort!((a, b) {
                auto aLoc = (!a.tree.isValid) ? a.location : a.tree.location;
                auto bLoc = (!b.tree.isValid) ? b.location : b.tree.location;
                int c = aLoc.start.opCmp2(bLoc.start, true);
                if (c)
                    return c < 0;
                c = aLoc.end.opCmp2(bLoc.end, true);
                if (c)
                    return c < 0;

                aLoc = getDeclaratorLoc(a);
                bLoc = getDeclaratorLoc(b);
                c = aLoc.start.opCmp2(bLoc.start, true);
                if (c)
                    return c < 0;
                c = aLoc.end.opCmp2(bLoc.end, true);

                return cmpDeclarationLoc(a, b, semantic);
            });
            Declaration firstDeclWithDeclarator = declarationsSorted[0];
            declarationsSorted.sort!((a, b) {
                if (a.tree.isValid && a.tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier"
                    && b.declaratorTree.isValid)
                    return false;
                if (b.tree.isValid && b.tree.nonterminalID == nonterminalIDFor!"ElaboratedTypeSpecifier"
                    && a.declaratorTree.isValid)
                    return true;
                auto aLoc = getDeclaratorLoc(a);
                auto bLoc = getDeclaratorLoc(b);
                int c = aLoc.start.opCmp2(bLoc.start, true);
                if (c)
                    return c < 0;
                c = aLoc.end.opCmp2(bLoc.end, true);

                return cmpDeclarationLoc(a, b, semantic);
            });

            Tree[] templateDeclarations = findParentTemplateDeclarations(tree, semantic);

            {
                size_t i = 0;
                auto declarationTokens = sourceTokenManager.declarationTokens(
                        declarationsSorted[i]);
                auto tokensBefore = sourceTokenManager.collectTokens(templateDeclarations.length
                        ? templateDeclarations[$ - 1].start : tree.start);

                size_t startCompatible = tokensBefore.length;
                while (startCompatible && tokensBefore[startCompatible - 1].token.nodeType == NodeType.token
                        && isSpaceToken(tokensBefore[startCompatible - 1].token.content)
                        && tokensBefore[startCompatible - 1].token.start.context.filename
                        == declarationsSorted[i].location.nonMacroLocation.context.filename
                        && tokensBefore[startCompatible - 1].condition is declarationsSorted[i].condition
                        && (startCompatible == tokensBefore.length
                            || !tokensBefore[startCompatible].token.content.among("\n", "\r\n")
                            || !tokensBefore[startCompatible - 1].token.content.among("\n", "\r\n")))
                    startCompatible--;

                addCommentDecls(tokensBefore[0 .. startCompatible]);
                tokensBefore = tokensBefore[startCompatible .. $];
                if (tokensBefore.length && tokensBefore[0].token.nodeType != NodeType.token)
                {
                    tokensBefore = tokensBefore[1 .. $];
                }
                declarationTokens.tokensBefore = sourceTokenManager.sourceTokenAllocator.allocate(tokensBefore);
            }
            Tree[] separatorTokens;
            void addSeparatorTokens(Tree tree)
            {
                if (tree.nodeType == NodeType.array || (tree.nodeType == NodeType.nonterminal
                        && tree.nonterminalID == CONDITION_TREE_NONTERMINAL_ID))
                {
                    foreach (c; tree.childs)
                        addSeparatorTokens(c);
                }
                if (tree.nodeType == NodeType.token)
                {
                    assert(tree.content == ",");
                    separatorTokens ~= tree;
                }
            }

            if (tree.hasChildWithName("declarators"))
                addSeparatorTokens(tree.childByName("declarators"));
            separatorTokens.sort!((a, b) {
                auto aLoc = a.location;
                auto bLoc = b.location;
                int c = aLoc.start.opCmp2(bLoc.start, true);
                if (c)
                    return c < 0;
                c = aLoc.end.opCmp2(bLoc.end, true);
                if (c)
                    return c < 0;
                return false;
            });
            size_t separatorIndex;
            foreach (i; 0 .. declarationsSorted.length)
            {
                auto declarationTokens = sourceTokenManager.declarationTokens(
                        declarationsSorted[i]);

                if (declarationsSorted[i].tree.isValid)
                {
                    auto tokensBefore = sourceTokenManager.collectTokens(
                            declarationsSorted[i].tree.start);
                    sourceTokenManager.sourceTokenAllocator.append(
                            sourceTokenManager.declarationTokens(firstDeclWithDeclarator)
                            .tokensInside, tokensBefore);
                }

                sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                        sourceTokenManager.collectTokens(declarationsSorted[i].location.end));
                if (declarationsSorted[i].declaratorTree.isValid)
                    sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                            sourceTokenManager.collectTokens(getDeclaratorLoc(declarationsSorted[i])
                                .end));
                if (declarationsSorted[i].tree.isValid
                        && declarationsSorted[i].tree.nameOrContent.among("ClassSpecifier",
                            "ElaboratedTypeSpecifier", "EnumSpecifier", "TypeParameter"))
                {
                    sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                            sourceTokenManager.collectTokens(declarationsSorted[i].tree.end));
                }
                while (separatorIndex < separatorTokens.length)
                {
                    if (separatorTokens[separatorIndex].end <= (declarationsSorted[i].declaratorTree.isValid
                            ? getDeclaratorLoc(declarationsSorted[i]).end
                            : declarationsSorted[i].tree.end))
                        continue;

                    if (i + 1 < declarationsSorted.length && (!declarationsSorted[i + 1].declaratorTree.isValid
                            || separatorTokens[separatorIndex].start >= getDeclaratorLoc(declarationsSorted[i + 1])
                            .start))
                        break;

                    sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                            sourceTokenManager.collectTokens(separatorTokens[separatorIndex].end));
                    sourceTokenManager.collectTokens(separatorTokens[separatorIndex].end);
                    sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensAfter,
                            sourceTokenManager.collectTokensUntilLineEnd(separatorTokens[separatorIndex].end,
                                declarationsSorted[i].condition));

                    separatorIndex++;
                }
            }
            declarationsSorted.sort!((a, b) {
                auto aLoc = getDeclaratorLoc(a);
                auto bLoc = getDeclaratorLoc(b);
                int c = aLoc.end.opCmp2(bLoc.end, true);
                if (c)
                    return c > 0;
                c = aLoc.start.opCmp2(bLoc.start, true);
                if (c)
                    return c > 0;
                return cmpDeclarationLoc(a, b, semantic);
            });
            if (tree.nameOrContent == "SimpleDeclaration3")
            {
                auto declarationTokens = sourceTokenManager.declarationTokens(
                        declarationsSorted[$ - 1]);
                addCommentDecls(sourceTokenManager.collectTokens(tree.childs[1].start));
                sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensAfter,
                        sourceTokenManager.collectTokens(tree.childs[1].end)); // ";"
                sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensAfter,
                        sourceTokenManager.collectTokensUntilLineEnd(tree.childs[1].end,
                            declarationsSorted[$ - 1].condition));
                return;
            }
            foreach (i; 0 .. declarationsSorted.length)
            {
                auto declarationTokens = sourceTokenManager.declarationTokens(
                        declarationsSorted[i]);

                sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                        sourceTokenManager.collectTokens(tree.end));
                sourceTokenManager.sourceTokenAllocator.append(declarationTokens.tokensInside,
                        sourceTokenManager.collectTokensUntilLineEnd(tree.end,
                            declarationsSorted[i].condition));
                break;
            }
        }
        else if (tree.nameOrContent == "TemplateDeclaration")
        {
            visitTree(tree.childs[$ - 1]);
        }
        else if (tree.nameOrContent == "SimpleDeclaration3"
                || tree.nameOrContent.startsWith("FunctionDefinition"))
        {
            /* Normally it would contain declarations, but for template specializations, the declarations are not generated yet.*/
        }
        else
        {
            foreach (c; tree.childs)
                visitTree(c);
        }
    }

    sourceTokenManager.collectTokens(LocationX(LocationN(), sourceTokenManager.locationContextMap.getLocationContext(
            immutable(LocationContext)(null, LocationN(),
            LocationN.LocationDiff(), "", mergedFile.filename.name))));

    foreach (tree; mergedFile.mergedTrees)
    {
        visitTree(tree);
    }

    addCommentDecls(sourceTokenManager.collectTokens(LocationX.init, true));
    assert(sourceTokenManager.tokensLeft.data.length == 0);
}
