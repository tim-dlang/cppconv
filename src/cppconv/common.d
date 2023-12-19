
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.common;
import cppconv.cpptree;
import cppconv.locationstack;
import cppconv.logic;
import cppconv.stringtable;
import cppconv.utils;

alias LogicSystem = BoundLogicSystem;
alias Formula = LogicSystem.Formula;
alias FormulaLiteral = BoundLiteral;
alias FormulaType = LogicSystem.FormulaType;
alias Location = LocationX;

SimpleClassAllocator!(CppParseTreeStruct*) treeAllocator;
SimpleClassAllocator!(CppParseTreeStruct*) preprocTreeAllocator;
StringTable!(ubyte[0]) globalStringPool;
static assert(StringValue!(ubyte[0]).sizeof == 4);
