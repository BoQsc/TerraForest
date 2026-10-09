// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_world.hpp"
#include "region_world_archive.hpp"
#include <godot_cpp/core/object.hpp>

namespace terraforest {
class NativeBlockPager : public RefCounted {
    GDCLASS(NativeBlockPager,RefCounted)
    ObjectID world_id_;
    Ref<NativeRegionWorldArchive> archive_;
    bool owns_read_service_=false;
    struct Pending {BlockKey key;PackedByteArray checksum;};
    std::map<int64_t,Pending> pending_;
    std::set<BlockKey> pending_keys_;
    std::map<BlockKey,PackedByteArray> admitted_versions_;
    std::map<BlockKey,std::pair<uint64_t,uint64_t>> blocked_;
    std::map<BlockKey,uint64_t> retry_after_;
    std::vector<BlockKey> offsets_;
    PackedInt32Array committed_keys_;
    PackedByteArray committed_digests_,checkpoint_;
    bool indexed_=false,initialized_=false,grid_valid_=false;
    BlockKey grid_;
    size_t cursor_=0;
    uint64_t world_epoch_=0,ticks_=0;
    int64_t epoch_=0,index_revision_=0;
    double load_radius_=384,unload_radius_=512;
    double pressure_distance_=1e100;
    int chunk_limit_=1536;
    int scanned_=0,scan_high_=0,operations_=0,operation_high_=0;
    int64_t requested_=0,admitted_=0,evicted_=0,stale_=0,failed_=0,budget_deferred_=0;
    double last_ms_=0,max_ms_=0;
    NativeBlockWorld *world() const;
    static double distance_squared(BlockKey key,Vector3 point);
    PackedByteArray committed_digest(BlockKey key) const;
    void reset(NativeBlockWorld *blocks,const PackedByteArray &checkpoint);
    bool evict_one(NativeBlockWorld *blocks,Vector3 focus);
protected:
    static void _bind_methods();
public:
    ~NativeBlockPager();
    bool configure(NativeBlockWorld *blocks,const Ref<NativeRegionWorldArchive> &archive,double load_radius=384,double unload_radius=512,int chunk_limit=1536);
    bool step(Vector3 world_focus,const PackedByteArray &restore_checkpoint=PackedByteArray());
    PackedByteArray get_checkpoint() const {return checkpoint_;}
    void stop();
    Dictionary stats() const;
};
}
