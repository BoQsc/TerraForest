# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func inventory(trail:bool=true)->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for id in [102,201]:result.register_item(id,64)
	for id in [301,302,303]:result.register_item(id,1)
	if trail:
		for id in [304,305,306]:result.register_item(id,1)
	return result

func corpses(player:RefCounted)->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativeCorpseStore")
	result.configure(player,512,8);return result

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var player:=inventory();var store:=corpses(player);var repeat:=corpses(player)
	var found:Dictionary={};var valid:=true;var deterministic:=true;var drops:=0
	for i in 192:
		var id:int=store.create_corpse(Vector3(i,0,0),0,1703)
		var other:int=repeat.create_corpse(Vector3(i,0,0),0,1703)
		valid=valid and id>0 and id==other
		var state:Dictionary=store.snapshot(id);var pieces:=0
		deterministic=deterministic and state.slots==repeat.snapshot(other).slots
		for slot in state.slots.size():
			var row:Dictionary=state.slots[slot]
			if row.item in [304,305,306]:
				pieces+=1;valid=valid and row.count==1;found[row.item]={"id":id,"slot":slot};drops+=1
		valid=valid and state.capacity==8 and pieces<=1 and state.slots[0].item==201 and state.slots[1].item==102
	check(valid,"corpse creation retains compact loot and adds at most one trail piece")
	check(found.size()==3 and drops>35 and drops<95,"all trail pieces appear at a common but non-guaranteed rate in the fixed sample")
	check(deterministic,"same identities and seed reproduce the same new-corpse loot")
	var saved:PackedByteArray=store.capture_corpse_snapshot();var restored:=corpses(player)
	check(restored.restore_corpse_snapshot(saved) and restored.capture_corpse_snapshot()==saved,"saved corpse contents restore byte-for-byte without rerolling")
	# Simulates a valid pre-trail catalog/save; adding the catalog cannot add loot.
	var legacy:=corpses(inventory(false))
	for i in 16:legacy.create_corpse(Vector3.ZERO,0,1703)
	var legacy_bytes:PackedByteArray=legacy.capture_corpse_snapshot()
	check(restored.restore_corpse_snapshot(legacy_bytes) and restored.capture_corpse_snapshot()==legacy_bytes,"old contents remain unchanged after enabling the new clothing catalog")
	if not found.is_empty():
		var entry:Dictionary=found[found.keys()[0]];var before:Dictionary=store.snapshot(entry.id)
		var revision:int=player.snapshot().revision
		check(store.withdraw(entry.id,player,entry.slot,1,revision,before.store_revision).ok,"clothing transfers from corpse to the real backpack")
		var player_bytes:PackedByteArray=player.capture_storage_snapshot();var corpse_bytes:PackedByteArray=store.capture_corpse_snapshot()
		check(not store.withdraw(entry.id,player,entry.slot,1,revision,before.store_revision).ok and player.capture_storage_snapshot()==player_bytes and store.capture_corpse_snapshot()==corpse_bytes,"stale loot action cannot duplicate clothing")
		var loaded_player:=inventory();var loaded_corpses:=corpses(loaded_player)
		check(loaded_player.restore_storage_snapshot(player_bytes) and loaded_corpses.restore_corpse_snapshot(corpse_bytes) and loaded_corpses.snapshot(entry.id).slots[entry.slot].count==0,"save/restore retains the looted backpack item and empty corpse slot")
		var full:=inventory();var items:=PackedInt64Array()
		for i in 32:items.append(201);items.append(64)
		check(full.grant_items(items,full.snapshot().revision).ok,"full backpack fixture is populated")
		var full_store:=corpses(full);full_store.restore_corpse_snapshot(saved)
		var full_bytes:PackedByteArray=full.capture_storage_snapshot();var full_before:PackedByteArray=full_store.capture_corpse_snapshot()
		check(not full_store.withdraw(entry.id,full,entry.slot,1,full.snapshot().revision,full_store.snapshot(entry.id).store_revision).ok and full.capture_storage_snapshot()==full_bytes and full_store.capture_corpse_snapshot()==full_before,"full backpack rejects clothing loot without losing either side")
	print("CLOTHING_LOOT checks=",checks," failures=",failures);quit(1 if failures else 0)
