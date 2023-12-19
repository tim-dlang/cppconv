
//          Copyright Tim Schendekehl 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

module cppconv.ecs;
import core.memory;
import std.experimental.allocator.building_blocks.ascending_page_allocator;

alias EntityID = uint;

struct BlockInfo
{
    EntityID nextEntity;
    EntityID freeEntities;
}

class EntityManager
{
    immutable size_t pageSize;
    enum minComponentSize = 8;
    immutable EntityID maxNumEntities;
    immutable EntityID entitiesPerBlock;

    BlockInfo[uint] blockPerHint;
    EntityID nextEntityBlock;

    ComponentManagerBase[] components;

    this(EntityID maxNumEntities)
    {
        this.maxNumEntities = maxNumEntities;
        pageSize = core.memory.pageSize;
        entitiesPerBlock = cast(EntityID)(pageSize / minComponentSize);
    }

    EntityID addEntity(uint hint)
    {
        auto block = hint in blockPerHint;
        if (block is null)
        {
            blockPerHint[hint] = BlockInfo();
            block = hint in blockPerHint;
        }
        if (block.freeEntities == 0)
        {
            if (nextEntityBlock + entitiesPerBlock > maxNumEntities)
                assert(0);
            block.nextEntity = nextEntityBlock;
            block.freeEntities = entitiesPerBlock;
            nextEntityBlock += entitiesPerBlock;
            foreach (c; components)
                c.blockAdded();
        }
        EntityID r = block.nextEntity;
        block.nextEntity++;
        block.freeEntities--;
        return r;
    }

    void clear()
    {
        foreach (c; components)
            c.clear();
        components = [];
        blockPerHint = null;
        nextEntityBlock = 0;
    }
}

abstract class ComponentManagerBase
{
    abstract void clear();
    abstract void blockAdded();
}

class ComponentManager(T) : ComponentManagerBase
{
    EntityManager entityManager;

    AscendingPageAllocator* allocator;

    enum size_t componentSize = (T.sizeof + EntityManager.minComponentSize - 1) / EntityManager
            .minComponentSize * EntityManager.minComponentSize;
    immutable size_t blockSize;

    EntityID entitiesInGC;

    void[] data;

    this(EntityManager entityManager)
    {
        this.entityManager = entityManager;
        entityManager.components ~= this;
        blockSize = entityManager.entitiesPerBlock * componentSize;
        assert(blockSize % entityManager.pageSize == 0);

        allocator = new AscendingPageAllocator(entityManager.maxNumEntities * componentSize);
        GC.addRoot(allocator);
        data = allocator.allocate(entityManager.maxNumEntities * componentSize);
        blockAdded();
    }

    ref T get(EntityID e)
    {
        assert(e < entityManager.maxNumEntities);
        return *cast(T*)(data.ptr + e * componentSize);
    }

    override void clear()
    {
        for (size_t i = 0; i < entitiesInGC; i += entityManager.entitiesPerBlock)
        {
            GC.removeRange(data.ptr + i * componentSize);
        }
        allocator.deallocateAll();
        GC.removeRoot(allocator);
        allocator = null;
        data = [];
    }

    override void blockAdded()
    {
        while (entitiesInGC < entityManager.nextEntityBlock)
        {
            GC.addRange(data.ptr + entitiesInGC * componentSize, blockSize);
            entitiesInGC += entityManager.entitiesPerBlock;
        }
    }
}

unittest
{
    EntityManager entityManager = new EntityManager(1_000_000);

    ComponentManager!int component1 = new ComponentManager!int(entityManager);

    foreach (i; 0 .. 1000)
    {
        auto e = entityManager.addEntity(i % 5 == 0);
        int* x = &component1.get(e);
        *x = cast(int) i;
        writeln(e, " ", *x);
    }
}
