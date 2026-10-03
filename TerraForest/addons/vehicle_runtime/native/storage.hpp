// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace terraforest {
class NativeVehicleStorage : public godot::RefCounted {
    GDCLASS(NativeVehicleStorage,godot::RefCounted)
protected: static void _bind_methods();
public:
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    godot::PackedByteArray encode(godot::Transform3D pose) const;
    godot::Dictionary decode(const godot::PackedByteArray &data) const;
};
}
