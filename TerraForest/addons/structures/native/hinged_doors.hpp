// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <map>
namespace terraforest {
class NativeHingedDoors : public godot::RefCounted {
    GDCLASS(NativeHingedDoors,godot::RefCounted)
    std::map<int64_t,godot::PackedFloat32Array> opened;
    static bool decode(const godot::PackedByteArray &,std::map<int64_t,godot::PackedFloat32Array> *);
protected: static void _bind_methods();
public:
    godot::Dictionary toggle(NativeStaticBatch *,int64_t,const godot::AABB &);
    void forget(int64_t id){opened.erase(id);}
    bool is_open(int64_t id) const {return opened.count(id)!=0;}
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &b) const {return decode(b,nullptr);}
    bool restore_storage_snapshot(const godot::PackedByteArray &);
};
}
