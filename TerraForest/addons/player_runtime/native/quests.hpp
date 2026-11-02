// SPDX-License-Identifier: 0BSD
#pragma once
#include "inventory.hpp"
#include "progression.hpp"
#include "reward_inbox.hpp"
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <vector>

namespace terraforest {
class NativeQuestLog : public godot::RefCounted {
    GDCLASS(NativeQuestLog,godot::RefCounted)
    struct Location {
        int64_t key=0;
        godot::String layout,title;
        godot::Vector3i origin;
        godot::Vector3 marker;
        godot::AABB bounds;
        uint32_t rotation=0,coins=0,xp=0,completed=0;
        std::vector<int64_t> residents,containers;
    };
    std::vector<Location> locations;
    int64_t seed=-1,currency=0,active=0,revision=0;
    uint32_t phase=0,cycle=0,defeated=0;
    uint32_t introduction=0;
    bool arrived=false;
    uint32_t search_ms=0;
    static constexpr int MAX_LOCATIONS=128,MAX_RESIDENTS=32,MAX_CONTAINERS=16,MAX_BYTES=131072;
    static bool valid(const Location &location);
    static bool valid_ownership(const std::vector<Location> &locations);
    static bool same_definition(const Location &left,const Location &right);
    static godot::Dictionary describe(const Location &location);
    Location *find(int64_t key);
    const Location *find(int64_t key) const;
    godot::Dictionary result(bool ok,const char *reason) const;
    bool decode(const godot::PackedByteArray &data,std::vector<Location> &parsed,int64_t &world_seed,int64_t &active_key,uint32_t &state,uint32_t &iteration,uint32_t &mask) const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Ref<NativePlayerInventory> &inventory,int64_t coin_item);
    godot::Dictionary register_locations(int64_t world_seed,const godot::Array &definitions);
    godot::Array get_locations() const;
    godot::Dictionary snapshot() const;
    godot::Dictionary accept(int64_t key,int64_t expected_revision);
    godot::Dictionary initialize_introduction(int64_t expected_revision);
    godot::Dictionary talk_to_trader(int64_t expected_revision);
    godot::Dictionary accept_first_visit(int64_t key,const godot::Ref<NativePlayerInventory> &inventory,int64_t expected_revision,int64_t inventory_revision);
    godot::Dictionary begin_reset(int64_t expected_revision);
    godot::Dictionary finish_reset(int64_t token,bool committed,int64_t expected_revision);
    godot::Dictionary record_defeated(int64_t resident_key,int64_t token);
    bool advance_search(godot::Vector3 position,int64_t milliseconds);
    godot::Dictionary abandon(int64_t expected_revision);
    godot::Dictionary claim(const godot::Ref<NativeRewardInbox> &inbox,const godot::Ref<NativePlayerProgression> &progression,int64_t expected_revision);
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
