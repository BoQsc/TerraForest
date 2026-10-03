// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
namespace terraforest {
class NativePlayerPose : public godot::RefCounted {
    GDCLASS(NativePlayerPose,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    godot::PackedByteArray encode(godot::Vector3 position,double yaw,double pitch,bool fly,int64_t tool) const;
    godot::Dictionary decode(const godot::PackedByteArray &data) const;
};
}
