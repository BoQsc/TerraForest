// SPDX-License-Identifier: 0BSD
#pragma once
#include "inventory.hpp"
#include "progression.hpp"
#include <array>

namespace terraforest {
class NativePlayerSurvival : public godot::RefCounted {
    GDCLASS(NativePlayerSurvival,godot::RefCounted)
    struct Item { int64_t id=0,food=0,xp=0,effect=0,duration=0,read=0; };
    struct Effect { int64_t id=0,damage=0,learning=0,remaining=0; };
    std::array<Item,32> items{};
    std::array<Effect,8> effects{};
    int64_t item_count=0,effect_count=0,revision=0;
    static constexpr int64_t FULL=3600000;
    int64_t food=FULL;
    godot::Dictionary result(bool ok,const char *reason) const;
    int64_t effect_index(int64_t identity) const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::PackedInt64Array &item_rules,const godot::PackedInt64Array &effect_rules);
    bool advance(int64_t elapsed_ms);
    int64_t scale_damage(int64_t base) const;
    int64_t scale_experience(int64_t base) const;
    godot::Dictionary use(const godot::Ref<NativePlayerInventory> &inventory,const godot::Ref<NativePlayerProgression> &progression,int64_t slot,int64_t expected_inventory,int64_t expected_revision);
    godot::Dictionary snapshot() const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
