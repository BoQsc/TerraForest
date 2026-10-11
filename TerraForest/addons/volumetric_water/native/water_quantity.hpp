// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <map>
namespace terraforest {
// Authoritative finite quantities. No geometry, ticking or floating-point volume.
// Worker/server owned: callers serialize commands; revision checks are not locks.
class NativeWaterQuantity : public godot::RefCounted {
    GDCLASS(NativeWaterQuantity, godot::RefCounted)
    struct Record { int64_t amount=0, capacity=0; };
    std::map<int64_t,Record> records;
    int64_t next_id=1, revision=0, total=0;
    static constexpr int64_t limit=9007199254740991LL;
    static constexpr size_t max_records=4096;
    godot::Dictionary result(bool ok, const char *reason, int64_t moved=0) const;
protected:
    static void _bind_methods();
public:
    godot::Dictionary create(int64_t capacity_ml,int64_t initial_ml,int64_t expected);
    godot::Dictionary remove_empty(int64_t id,int64_t expected);
    godot::Dictionary transfer(int64_t source,int64_t destination,int64_t amount_ml,int64_t expected);
    godot::Dictionary inspect(int64_t id) const;
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_snapshot() const;
    bool restore_snapshot(const godot::PackedByteArray &bytes);
};
}
