// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <array>
#include <unordered_map>
namespace terraforest {
class NativePlayerInventory : public godot::RefCounted {
    GDCLASS(NativePlayerInventory,godot::RefCounted)
    friend class NativeContainerStore;
    struct Stack {int64_t item=0,count=0,wear=0,water_ml=0;};
    std::array<Stack,32> slots{};
    std::unordered_map<int64_t,int64_t> limits;
    // Containers share one private immutable schema instead of copying its
    // hash table into every stored inventory. Ordinary player inventories own it.
    godot::Ref<NativePlayerInventory> catalog_owner;
    const std::unordered_map<int64_t,int64_t> &catalog() const {return catalog_owner.is_valid()?catalog_owner->limits:limits;}
    std::unordered_map<int64_t,int64_t> durability;
    const std::unordered_map<int64_t,int64_t> &durable_catalog() const {return catalog_owner.is_valid()?catalog_owner->durability:durability;}
    int64_t revision=0;
    int slot_limit=32;
    godot::Dictionary result(bool ok,const char *reason) const;
    godot::Dictionary apply_costs(const godot::PackedInt64Array &costs,int64_t expected,bool commit);
    godot::Dictionary apply_grants(const godot::PackedInt64Array &items,int64_t expected,bool commit);
protected:
    static void _bind_methods();
public:
    int64_t get_revision() const {return revision;}
    bool has_item(int64_t item) const {return catalog().find(item)!=catalog().end();}
    static constexpr int64_t WATER_CAPACITY_ML=1000000;
    static bool water_container(int64_t item){return item>=401&&item<=411;}
    bool exchange_water(int64_t slot,bool pour,int64_t expected,int64_t millilitres);
    bool exchange_bucket(int64_t slot,bool pour,int64_t expected,int64_t litres=1);
    bool register_durable(int64_t item,int64_t maximum);
    int64_t max_durability(int64_t item) const;
    godot::Dictionary wear_tool(int64_t slot,int64_t amount,int64_t expected);
    bool register_item(int64_t item,int64_t limit);
    godot::Dictionary snapshot() const;
    godot::Dictionary grant(int64_t item,int64_t count,int64_t expected);
    godot::Dictionary grant_durable(int64_t item,int64_t wear,int64_t expected);
    godot::Dictionary grant_items(const godot::PackedInt64Array &items,int64_t expected);
    godot::Dictionary can_receive(const godot::PackedInt64Array &items,int64_t expected);
    godot::Dictionary exchange_items(const godot::PackedInt64Array &costs,const godot::PackedInt64Array &outputs,int64_t expected);
    godot::Dictionary consume(int64_t slot,int64_t count,int64_t expected);
    godot::Dictionary consume_items(const godot::PackedInt64Array &costs,int64_t expected);
    godot::Dictionary can_afford(const godot::PackedInt64Array &costs,int64_t expected);
    godot::Dictionary transfer(int64_t from,int64_t to,int64_t count,int64_t expected);
    godot::Dictionary transfer_to(const godot::Ref<NativePlayerInventory> &destination,int64_t slot,int64_t count,int64_t expected_source,int64_t expected_destination);
    godot::Dictionary restore(const godot::Dictionary &snapshot,int64_t expected);
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
