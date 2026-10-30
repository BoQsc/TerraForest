// SPDX-License-Identifier: 0BSD
#pragma once
#include "model_render_page.hpp"
#include "region_world_archive.hpp"
#include <godot_cpp/classes/node.hpp>
#include <deque>
#include <unordered_map>

namespace terraforest {
class NativeModelHorizon : public Node {
    GDCLASS(NativeModelHorizon,Node)
    struct Location {uint64_t page=0;size_t slot=0;};
    struct Collection {
        uint64_t id=0,epoch=0;
        PackedByteArray checkpoint;
        int64_t lease=0;
        size_t seeds=0;
        int64_t change_cursor=0;
        std::unordered_map<int64_t,Location> instances,drawn;
        std::map<BlockKey,std::set<uint64_t>> available;
        std::set<int64_t> changed_during_seed;
    };
    struct DrawPage {
        uint64_t collection=0,node=0;
        BlockKey origin;
        std::vector<ModelPlacementRecord> records,drawn;
        AABB bounds;
        uint32_t gpu_count=0;
        int shadow=-1;
    };
    struct Seed {
        uint64_t collection=0,epoch=0;
        BlockKey region;
        int64_t after=0,ticket=0;
        size_t offset=0;
        PackedByteArray checksum;
        std::shared_ptr<ModelRenderPageData> data;
    };
    Ref<NativeRegionWorldArchive> archive;
    std::map<uint64_t,Collection> collections;
    std::map<uint64_t,DrawPage> pages;
    std::set<uint64_t> dirty;
    std::deque<Seed> seeds;
    uint64_t next_page=1,byte_limit=128*1024*1024,records=0,rendered=0,gpu_bytes=0;
    uint64_t uploads=0,uploaded_bytes=0,reads=0,last_records=0,last_uploads=0,last_usec=0,shadow_cursor=0;
    bool advancing=false,capacity_error=false;
    int read_slots=0;
    String error;
    static constexpr uint64_t RECORD_CHARGE=512,PAGE_CHARGE=2048,SEED_CHARGE=256,READ_CHARGE=5600328;
    static constexpr size_t PAGE_CAPACITY=256;
    NativeStaticBatch *source(uint64_t identity)const;
    MultiMeshInstance3D *node(uint64_t identity)const;
    uint64_t charged_bytes()const;
    bool assign(Collection &collection,int64_t identity,const NativeStaticBatch::Placement &transform);
    void erase(Collection &collection,int64_t identity);
    void erase_drawn(Collection &collection,int64_t identity);
    void remove_page(uint64_t identity);
    void discard_collection(Collection &collection);
    bool seed_collection(Collection &collection,NativeStaticBatch *batch);
    void cancel_seeds(uint64_t collection);
    bool advance_seed(Seed &seed,Collection &collection,NativeStaticBatch *batch);
    bool upload(uint64_t identity);
    void refresh_shadow(DrawPage &page);
protected:
    static void _bind_methods();
public:
    ~NativeModelHorizon();
    bool configure(const Ref<NativeRegionWorldArchive> &archive,const Array &models,const Dictionary &checkpoints,int64_t bytes=128*1024*1024);
    void clear();
    void advance(int64_t max_records=1024,int64_t max_uploads=2,int64_t max_usec=1500);
    void _process(double delta)override;
    Dictionary statistics()const;
    PackedInt64Array represented_ids(NativeStaticBatch *batch)const;
    Dictionary visual_record(NativeStaticBatch *batch,int64_t identity)const;
};
}
