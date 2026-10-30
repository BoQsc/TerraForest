#pragma once
#include "block_world.hpp"
#include "block_map_region.hpp"
#include "region_world_archive.hpp"
#include <atomic>

namespace terraforest {
class BlockHorizon {
    NativeBlockWorld &world;
    Node3D *root=nullptr;
    struct Region {uint64_t version=1,retry=0;bool ready=false;};
    struct Visual {MeshInstance3D *instance=nullptr;uint64_t bytes=0;int triangles=0;};
    std::map<BlockKey,Region> regions;
    std::map<BlockKey,Visual> visuals;
    Ref<NativeRegionWorldArchive> archive;
    PackedByteArray checkpoint;
    uint64_t seen_mutation=UINT64_MAX,seen_epoch=UINT64_MAX,ticks=0,bytes=0;
    static constexpr uint64_t BYTE_LIMIT=128*1024*1024;
    uint64_t published=0,rejected=0,failed=0,blocked=0;
    double upload_max_ms=0;
    bool enabled=false,active=false,stopping=false,pending=false,ready=false;
    std::thread worker;
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<uint64_t> serial{1};
    uint64_t active_serial=0,active_version=0;
    BlockKey active_region;
    int64_t read_ticket=0;
    PackedByteArray read_digest;
    std::map<BlockKey,BlockChunk> source;
    Ref<NativeBlockMapRegion> decoded;
    BlockBake result;
    bool result_last=false;
    std::set<BlockKey> result_keys;
    void run();
    void start(std::map<BlockKey,BlockChunk> &&chunks,const Ref<NativeBlockMapRegion> &packet={});
    bool deliver(BlockBake &&bake,bool last,uint64_t ticket,const std::set<BlockKey> &keys={});
    void erase(BlockKey key);
    void reset();
    void sync();
    void publish(BlockBake &&bake);
public:
    explicit BlockHorizon(NativeBlockWorld &owner):world(owner){}
    ~BlockHorizon();
    void set_enabled(bool value);
    void set_archive(const Ref<NativeRegionWorldArchive> &value,const PackedByteArray &pin);
    void invalidate(BlockKey key);
    void near_changed(BlockKey key);
    void retain(BlockKey key,const BlockVisual &visual);
    void step();
    Dictionary stats() const;
};
}
