// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <array>
#include <unordered_map>
namespace terraforest {
class NativePlayerInventory : public godot::RefCounted {
    GDCLASS(NativePlayerInventory,godot::RefCounted)
    struct Stack {int64_t item=0,count=0;};
    std::array<Stack,32> slots{};
    std::unordered_map<int64_t,int64_t> limits;
    int64_t revision=0;
    godot::Dictionary result(bool ok,const char *reason) const;
protected:
    static void _bind_methods();
public:
    bool register_item(int64_t item,int64_t limit);
    godot::Dictionary snapshot() const;
    godot::Dictionary grant(int64_t item,int64_t count,int64_t expected);
    godot::Dictionary consume(int64_t slot,int64_t count,int64_t expected);
    godot::Dictionary transfer(int64_t from,int64_t to,int64_t count,int64_t expected);
    godot::Dictionary restore(const godot::Dictionary &snapshot,int64_t expected);
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
