#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <deque>

namespace terraforest {
// Scene-thread editor journal. Weak collection identities, fixed-size deltas;
// neither whole collection snapshots nor per-instance scene objects are retained.
class NativeStaticHistory : public RefCounted {
    GDCLASS(NativeStaticHistory,RefCounted)
    struct Edit {
        uint64_t collection=0;
        int64_t id=0;
        NativeStaticBatch::Placement before{},after{};
        bool had_before=false,has_after=false;
    };
    std::map<uint64_t,uint64_t> revisions;
    std::deque<Edit> undo_edits,redo_edits;
    uint64_t byte_limit=4*1024*1024,barriers=0,unrecorded=0;
    int step_limit=256;
    bool busy=false;
    static NativeStaticBatch *resolve(uint64_t id);
    bool synchronize();
    bool registered(NativeStaticBatch *collection) const;
    void clear_records();
    void remember(const Edit &edit);
    void publish(NativeStaticBatch *collection);
    bool replay(bool backwards,const AABB &protection);
    bool region_referenced(uint64_t collection,BlockKey region) const;
    bool transfer_region(NativeStaticBatch *collection,const PackedByteArray &packet,bool restore);
    static PackedFloat32Array packed(const NativeStaticBatch::Placement &value);
protected:
    static void _bind_methods();
public:
    int64_t begin_region_admission(NativeStaticBatch *collection,const PackedByteArray &packet);
    Dictionary advance_region_admission(NativeStaticBatch *collection,int64_t ticket,int64_t max_records,int64_t max_hash_bytes,int64_t max_usec);
    bool cancel_region_admission(NativeStaticBatch *collection,int64_t ticket);
    bool region_has_history(NativeStaticBatch *collection,Vector3i region);
    bool unload_region(NativeStaticBatch *collection,const PackedByteArray &packet){return transfer_region(collection,packet,false);}
    bool restore_region(NativeStaticBatch *collection,const PackedByteArray &packet){return transfer_region(collection,packet,true);}
    bool configure(const Array &collections,int64_t bytes,int64_t steps);
    bool clear_history();
    int64_t insert(NativeStaticBatch *collection,const PackedFloat32Array &transform,const AABB &protection);
    bool erase(NativeStaticBatch *collection,int64_t id);
    bool update(NativeStaticBatch *collection,int64_t id,const PackedFloat32Array &transform,const AABB &protection);
    bool undo(const AABB &protection) {return replay(true,protection);}
    bool redo(const AABB &protection) {return replay(false,protection);}
    Dictionary stats();
};
}
