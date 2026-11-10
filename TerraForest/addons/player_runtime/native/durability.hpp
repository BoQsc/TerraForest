// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <map>
#include <string>
namespace terraforest {
class NativePlayerInventory;
class NativeWorldDurability : public godot::RefCounted {
    friend class NativeDestructionCoordinator;
    GDCLASS(NativeWorldDurability,godot::RefCounted)
    struct Entry {int health,damage;};
    std::map<std::string,Entry> damaged;
    int64_t revision=0;
    static bool valid_key(const std::string &);
    void record_damage(const std::string &,int maximum,int amount);
    static bool decode_damage_patch(const godot::PackedByteArray &,std::map<std::string,Entry> &);
    static bool decode(const godot::PackedByteArray &,std::map<std::string,Entry> *);
    godot::Dictionary quote_hit(godot::String key,int64_t maximum,int64_t amount) const;
protected: static void _bind_methods();
public:
    godot::Dictionary hit(godot::String key,int64_t maximum,int64_t amount);
    godot::Dictionary preview_harvest(godot::String key,int64_t maximum,int64_t amount,int64_t damage_per_item,int64_t finishing_bonus) const;
    godot::Dictionary harvest_hit(godot::String key,int64_t maximum,int64_t amount,int64_t item,int64_t damage_per_item,int64_t finishing_bonus,const godot::Ref<NativePlayerInventory> &inventory,int64_t expected_revision);
    godot::Dictionary repair(godot::String key,int64_t maximum,int64_t amount);
    int64_t damage(godot::String key,int64_t maximum) const;
    void forget(godot::String key);
    int64_t record_count() const {return damaged.size();}
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &b) const {return decode(b,nullptr);}
    bool restore_storage_snapshot(const godot::PackedByteArray &);
    godot::Dictionary damage_patch_state() const;
    godot::Dictionary select_damage_keys(godot::AABB bounds,const godot::PackedStringArray &identities,int64_t expected_revision,int64_t expected_owner) const;
    godot::PackedByteArray capture_damage_patch(const godot::PackedStringArray &,int64_t expected_revision,int64_t expected_owner) const;
    bool validate_damage_patch(const godot::PackedByteArray &) const;
    godot::Dictionary restore_damage_patch(const godot::PackedByteArray &,int64_t expected_revision,int64_t expected_owner);
};
}
