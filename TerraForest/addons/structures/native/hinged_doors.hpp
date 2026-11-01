// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <map>
namespace terraforest {
class NativeHingedDoors : public godot::RefCounted {
    GDCLASS(NativeHingedDoors,godot::RefCounted)
    std::map<int64_t,godot::PackedFloat32Array> opened;
    struct Motion {
        double elapsed=0;
        bool target=true;
        godot::PackedFloat32Array last;
        bool blocked=false;
    };
    std::map<int64_t,Motion> motions;
    godot::PackedFloat32Array opening_curve,closing_curve;
    godot::PackedByteArray curve_signature;
    double fraction(const Motion &) const;
    godot::AABB leaf{godot::Vector3(0,0,-0.07),godot::Vector3(1,2.2,0.14)};
    godot::Vector3 pivot;
    double opening_degrees=90.0;
    bool configured=false;
    uint64_t revision=0;
    bool state_busy=false;
    bool decode_door_patch(const godot::PackedByteArray &,std::vector<int64_t> &,std::map<int64_t,godot::PackedFloat32Array> &,std::map<int64_t,Motion> &) const;
    bool legacy_profile() const;
    godot::PackedFloat32Array swing(const godot::PackedFloat32Array &) const;
    godot::PackedFloat32Array pose_at(const godot::PackedFloat32Array &,double) const;
    godot::AABB sweep_bounds(const godot::Transform3D &) const;
    godot::String obstruction(NativeStaticBatch *,const godot::PackedFloat32Array &,const godot::AABB &) const;
    bool decode(const godot::PackedByteArray &,std::map<int64_t,godot::PackedFloat32Array> *,std::map<int64_t,Motion> * = nullptr) const;
protected: static void _bind_methods();
public:
    bool configure(const godot::AABB &,godot::Vector3,double);
    bool configure_animation(const godot::PackedFloat32Array &,const godot::PackedFloat32Array &);
    godot::Dictionary toggle(NativeStaticBatch *,int64_t,const godot::AABB &);
    godot::Dictionary animate_toggle(NativeStaticBatch *,int64_t,const godot::AABB &);
    int64_t advance(NativeStaticBatch *,double);
    godot::Dictionary motion_state(int64_t) const;
    godot::PackedInt64Array moving_ids() const {godot::PackedInt64Array ids;for(const auto &entry:motions)ids.push_back(entry.first);return ids;}
    bool is_moving(int64_t id) const {return motions.count(id)!=0;}
    bool is_blocked(int64_t id) const {auto it=motions.find(id);return it!=motions.end()&&it->second.blocked;}
    int64_t moving_count() const {return motions.size();}
    void forget(int64_t id){if(state_busy)return;const auto changes=opened.erase(id)+motions.erase(id);if(changes)++revision;}
    bool is_open(int64_t id) const {auto it=motions.find(id);return it==motions.end()?opened.count(id)!=0:it->second.target==1;}
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &b) const {return decode(b,nullptr);}
    bool restore_storage_snapshot(const godot::PackedByteArray &);
    godot::Dictionary door_patch_state() const;
    godot::PackedByteArray capture_door_patch(const godot::PackedInt64Array &,int64_t expected_revision,int64_t expected_owner) const;
    bool validate_door_patch(const godot::PackedByteArray &) const;
    godot::Dictionary restore_door_patch(const godot::PackedByteArray &,int64_t expected_revision,int64_t expected_owner);
};
}
