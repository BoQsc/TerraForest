// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_world.hpp"
#include <godot_cpp/classes/occluder_instance3d.hpp>

namespace terraforest {
// Main-thread adapter for exact, opaque near-block geometry. Nodes belong to
// their source mesh; no render-server readback, proxy walls or saved state.
class BlockOcclusion {
    NativeBlockWorld &world;
    struct Entry { OccluderInstance3D *node=nullptr; uint64_t bytes=0; bool stale=false; };
    std::map<BlockKey,Entry> entries;
    std::deque<BlockKey> pending;
    bool enabled=false,dirty=true;
    double radius=96;
    int limit=128;
    uint64_t budget=2*1024*1024,bytes=0;
    Vector3 selection_focus;
    uint64_t scans=0,published=0,invalidations=0,skipped_large=0;
    double last_us=0,max_us=0;
    int last_uploads=0,max_uploads=0;
    static constexpr uint64_t CHUNK_BYTES=256*1024;
    void select();
    void hide(Entry &entry);
public:
    explicit BlockOcclusion(NativeBlockWorld &owner):world(owner){}
    bool configure(bool value,double distance,int count,int64_t byte_limit);
    void changed(){dirty=true;}
    void invalidate(BlockKey key);
    void forget(BlockKey key); // Called immediately before the source mesh dies.
    void step();
    void flush(); // Explicit offline operation, like flush_bakes().
    Dictionary stats() const;
};
}
