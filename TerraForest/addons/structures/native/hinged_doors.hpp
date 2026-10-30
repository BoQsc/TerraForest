// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <map>
namespace terraforest {
class NativeHingedDoors : public godot::RefCounted {
    GDCLASS(NativeHingedDoors,godot::RefCounted)
    std::map<int64_t,godot::PackedFloat32Array> opened;
    godot::AABB leaf{godot::Vector3(0,0,-0.07),godot::Vector3(1,2.2,0.14)};
    godot::Vector3 pivot;
    double opening_degrees=90.0;
    bool configured=false;
    bool legacy_profile() const;
    godot::PackedFloat32Array swing(const godot::PackedFloat32Array &) const;
    godot::AABB sweep_bounds(const godot::Transform3D &) const;
    bool decode(const godot::PackedByteArray &,std::map<int64_t,godot::PackedFloat32Array> *) const;
protected: static void _bind_methods();
public:
    bool configure(const godot::AABB &,godot::Vector3,double);
    godot::Dictionary toggle(NativeStaticBatch *,int64_t,const godot::AABB &);
    void forget(int64_t id){opened.erase(id);}
    bool is_open(int64_t id) const {return opened.count(id)!=0;}
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &b) const {return decode(b,nullptr);}
    bool restore_storage_snapshot(const godot::PackedByteArray &);
};
}
