// SPDX-License-Identifier: 0BSD
#pragma once
#include "durability.hpp"
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <array>
namespace terraforest {
// One bounded block-store/durability transaction. Geometry remains a separate
// publication gate; successful store commit must never imply rendered readiness.
class NativeDestructionCoordinator : public godot::RefCounted {
    GDCLASS(NativeDestructionCoordinator,godot::RefCounted)
    godot::Ref<NativeWorldDurability> owner;
    godot::Object *block_owner=nullptr;
    std::map<std::string,NativeWorldDurability::Entry> staged;
    std::array<std::string,64> removed_keys;
    int removed_count=0;
    int64_t expected_revision=0;
    bool executing=false,armed=false,committed=false;
protected: static void _bind_methods();
public:
    godot::Dictionary execute(godot::Object *blocks,const godot::Ref<NativeWorldDurability> &durability,
        const godot::PackedInt32Array &records,int64_t offset,godot::Vector3 center,int64_t count);
    bool commit_damage();
};
}
