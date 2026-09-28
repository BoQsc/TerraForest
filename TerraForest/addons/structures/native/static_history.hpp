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
    static PackedFloat32Array packed(const NativeStaticBatch::Placement &value);
protected:
    static void _bind_methods();
public:
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
