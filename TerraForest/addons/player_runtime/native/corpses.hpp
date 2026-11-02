// SPDX-License-Identifier: 0BSD
#pragma once
#include "containers.hpp"
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <vector>
namespace terraforest {
class NativeCorpseStore : public NativeContainerStore {
    GDCLASS(NativeCorpseStore,NativeContainerStore)
    struct Corpse {godot::Vector3 position;float yaw=0;uint32_t missing=0;godot::PackedFloat32Array pose;int64_t resident=0,anchor=0;};
    std::map<int64_t,Corpse> records;int64_t next_id=1;
    std::map<int64_t,int64_t> resident_corpses;
    std::map<int64_t,int64_t> anchor_corpses;
    struct PatchEntry {int64_t resident=0,anchor=0,id=0;Corpse corpse;godot::PackedByteArray inventory;};
    static bool valid_pose(const godot::PackedFloat32Array &);
    static bool valid_owner(int64_t resident,int64_t anchor);
    bool decode_corpse_patch(const godot::PackedByteArray &,std::vector<PatchEntry> &)const;
    bool decode(const godot::PackedByteArray &,std::map<int64_t,Corpse> &,int64_t &,godot::PackedByteArray &)const;
protected:
    bool supports_locks() const override {return false;}
    static void _bind_methods();
public:
    int64_t create_corpse(godot::Vector3 position,double yaw,int64_t seed,int64_t resident=0,int64_t anchor=0);
    godot::Dictionary corpse_patch_state()const;
    godot::PackedByteArray capture_corpse_patch(const godot::PackedInt64Array &residents,const godot::PackedInt64Array &anchors,int64_t revision,int64_t owner)const;
    bool validate_corpse_patch(const godot::PackedByteArray &)const;
    godot::Dictionary restore_corpse_patch(const godot::PackedByteArray &,int64_t revision,int64_t owner);
    bool update_corpse(int64_t id,godot::Vector3 position,double yaw,int64_t missing,const godot::PackedFloat32Array &pose);
    godot::Dictionary corpse(int64_t id)const;
    godot::PackedInt64Array corpse_ids()const;
    godot::PackedInt64Array nearby_corpses(godot::Vector3 focus,double radius,const godot::PackedInt64Array &excluded)const;
    bool foreign_corpse_in_region(godot::AABB bounds,const godot::PackedInt64Array &residents)const;
    bool erase_corpse(int64_t id);
    godot::PackedByteArray capture_corpse_snapshot()const;
    bool validate_corpse_snapshot(const godot::PackedByteArray &bytes)const;
    bool validate_snapshot(const godot::PackedByteArray &bytes)const override{return validate_corpse_snapshot(bytes);}
    bool restore_corpse_snapshot(const godot::PackedByteArray &bytes);
};
}
