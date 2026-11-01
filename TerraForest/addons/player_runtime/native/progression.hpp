// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <array>

namespace terraforest {
class NativePlayerProgression : public godot::RefCounted {
    GDCLASS(NativePlayerProgression, godot::RefCounted)
    struct Skill { int64_t id=0, maximum=0, bonus=0, rank=0; };
    std::array<Skill,32> skills{};
    int64_t count=0, experience=0, revision=0;
    static constexpr int64_t MAX_LEVEL=50;
    static int64_t threshold(int64_t level);
    static int64_t level_for(int64_t experience);
    int64_t available_points() const;
    godot::Dictionary result(bool ok,const char *reason) const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::PackedInt64Array &definitions);
    godot::Dictionary snapshot() const;
    godot::Dictionary award(int64_t amount,int64_t expected_revision);
    godot::Dictionary spend(int64_t skill,int64_t expected_revision);
    int64_t scale_action(int64_t skill,int64_t base) const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
