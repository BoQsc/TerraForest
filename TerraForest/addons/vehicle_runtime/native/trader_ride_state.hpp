// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
namespace terraforest {
// One trader/service, captured with the fleet and both inventories in the same
// compound save. Validation is pure native work, safe on the archive worker.
class NativeTraderRideState : public godot::RefCounted {
    GDCLASS(NativeTraderRideState,godot::RefCounted)
    godot::PackedByteArray data;
    static godot::Dictionary decode(const godot::PackedByteArray &bytes);
protected:
    static void _bind_methods();
public:
    godot::Dictionary snapshot() const;
    bool set_state(const godot::Dictionary &state);
    godot::PackedByteArray capture_storage_snapshot()const{return data;}
    bool validate_snapshot(const godot::PackedByteArray &bytes)const;
    bool restore_storage_snapshot(const godot::PackedByteArray &bytes);
};
}
