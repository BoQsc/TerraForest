// SPDX-License-Identifier: 0BSD
#pragma once
#include "containers.hpp"
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
namespace terraforest {
class NativeCorpseStore : public NativeContainerStore {
    GDCLASS(NativeCorpseStore,NativeContainerStore)
    struct Corpse {godot::Vector3 position;float yaw=0;uint32_t missing=0;godot::PackedFloat32Array pose;};
    std::map<int64_t,Corpse> records;int64_t next_id=1;
    bool decode(const godot::PackedByteArray &,std::map<int64_t,Corpse> &,int64_t &,godot::PackedByteArray &)const;
protected:
    static void _bind_methods();
public:
    int64_t create_corpse(godot::Vector3 position,double yaw,int64_t seed);
    bool update_corpse(int64_t id,godot::Vector3 position,double yaw,int64_t missing,const godot::PackedFloat32Array &pose);
    godot::Dictionary corpse(int64_t id)const;
    godot::PackedInt64Array corpse_ids()const;
    godot::PackedInt64Array nearby_corpses(godot::Vector3 focus,double radius,const godot::PackedInt64Array &excluded)const;
    bool erase_corpse(int64_t id);
    godot::PackedByteArray capture_corpse_snapshot()const;
    bool validate_corpse_snapshot(const godot::PackedByteArray &bytes)const;
    bool validate_snapshot(const godot::PackedByteArray &bytes)const override{return validate_corpse_snapshot(bytes);}
    bool restore_corpse_snapshot(const godot::PackedByteArray &bytes);
};
}
