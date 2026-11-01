// SPDX-License-Identifier: 0BSD
#pragma once
#include "inventory.hpp"
#include <map>
namespace terraforest {
// Sparse nonempty inventories for ONE stable model-asset collection. Main-thread
// mutation; byte validation reads only the immutable configured catalog.
class NativeContainerStore : public godot::RefCounted {
    GDCLASS(NativeContainerStore,godot::RefCounted)
protected:
    godot::Ref<NativePlayerInventory> schema;
    std::map<int64_t,godot::Ref<NativePlayerInventory>> contents;
    struct Lock {uint32_t remaining=0,maximum=0;uint64_t random_state=0;int64_t revision=0;};
    std::map<int64_t,Lock> locks;
    int64_t lockpick_item=0;
    int64_t lock_only_count=0;
    int64_t capacity=0,revision=0;
    int slot_count=32;
    int visible_slots(const godot::Ref<NativePlayerInventory> &inventory) const;
    godot::Ref<NativePlayerInventory> empty_inventory() const;
    godot::Dictionary move(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision,bool deposit);
    bool initialize_contents(int64_t id,const godot::PackedInt64Array &items);
    int64_t view_revision(int64_t id) const;
    void touch(int64_t id);
    virtual bool supports_locks() const {return true;}
protected:
    static void _bind_methods();
public:
    bool seed_contents(int64_t id,const godot::PackedInt64Array &items){return !items.is_empty()&&items.size()<=64&&initialize_contents(id,items);}
    bool configure(const godot::Ref<NativePlayerInventory> &prototype,int64_t max_containers,int64_t slots=32,int64_t pick_item=0);
    bool seed_lock(int64_t id,int64_t maximum,int64_t seed);
    bool is_locked(int64_t id) const {return locks.count(id)!=0;}
    bool requires_protection(int64_t id) const {return has_contents(id)||is_locked(id);}
    godot::Dictionary lock_state(int64_t id) const;
    godot::Dictionary attempt_unlock(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t player_revision,int64_t store_revision);
    godot::Dictionary damage_lock(int64_t id,int64_t damage,int64_t store_revision);
    godot::Dictionary snapshot(int64_t id) const;
    godot::PackedInt64Array get_ids() const;
    bool has_contents(int64_t id) const {return contents.count(id)!=0;}
    godot::Dictionary deposit(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision) {return move(id,player,slot,count,player_revision,store_revision,true);}
    godot::Dictionary withdraw(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision) {return move(id,player,slot,count,player_revision,store_revision,false);}
    godot::Dictionary drag_slots(int64_t id,const godot::Ref<NativePlayerInventory> &player,bool source_chest,bool target_chest,int64_t from,int64_t to,int64_t count,int64_t player_revision,int64_t store_revision);
    godot::PackedByteArray capture_storage_snapshot() const;
    godot::Dictionary container_patch_state() const;
    godot::PackedByteArray capture_container_patch(const godot::PackedInt64Array &ids,int64_t expected_revision,int64_t expected_owner) const;
    bool validate_container_patch(const godot::PackedByteArray &bytes) const;
    godot::Dictionary restore_container_patch(const godot::PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner);
    virtual bool validate_snapshot(const godot::PackedByteArray &bytes) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &bytes);
};
}
