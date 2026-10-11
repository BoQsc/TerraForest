// SPDX-License-Identifier: 0BSD
#pragma once
#include "inventory.hpp"
#include <map>
namespace terraforest {
// Sparse nonempty inventories for ONE stable model-asset collection. Main-thread
// mutation; byte validation reads only the immutable configured catalog.
class NativeContainerStore : public godot::RefCounted {
    GDCLASS(NativeContainerStore,godot::RefCounted)
    godot::Ref<NativePlayerInventory> schema;
    std::map<int64_t,godot::Ref<NativePlayerInventory>> contents;
    int64_t capacity=0,revision=0;
    godot::Ref<NativePlayerInventory> empty_inventory() const;
    godot::Dictionary move(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision,bool deposit);
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Ref<NativePlayerInventory> &prototype,int64_t max_containers);
    godot::Dictionary snapshot(int64_t id) const;
    godot::PackedInt64Array get_ids() const;
    bool has_contents(int64_t id) const {return contents.count(id)!=0;}
    godot::Dictionary deposit(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision) {return move(id,player,slot,count,player_revision,store_revision,true);}
    godot::Dictionary withdraw(int64_t id,const godot::Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision) {return move(id,player,slot,count,player_revision,store_revision,false);}
    godot::Dictionary drag_slots(int64_t id,const godot::Ref<NativePlayerInventory> &player,bool source_chest,bool target_chest,int64_t from,int64_t to,int64_t count,int64_t player_revision,int64_t store_revision);
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &bytes) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &bytes);
};
}
