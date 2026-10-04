# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	call_deferred("run")
func run() -> void:
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	for item in range(101,105): inventory.register_item(item,10)
	inventory.grant(101,15,0)
	inventory.grant(102,4,1)
	var before: Dictionary=inventory.snapshot()
	check(inventory.can_afford(PackedInt64Array([101,12,102,4]),before.revision).ok and inventory.snapshot()==before,"affordability does not mutate")
	for costs in [PackedInt64Array(),PackedInt64Array([101]),PackedInt64Array([101,1,999,1]),PackedInt64Array([101,1,102,5]),PackedInt64Array([101,10,101,6]),PackedInt64Array([101,32000001]),PackedInt64Array([101,-1])]:
		check(not inventory.consume_items(costs,before.revision).ok and inventory.snapshot()==before,"invalid or insufficient costs leave every slot and revision intact")
	check(not inventory.consume_items(PackedInt64Array([101,1]),0).ok and inventory.snapshot()==before,"stale debit rejected")
	check(inventory.consume_items(PackedInt64Array([101,10,101,2,102,4]),before.revision).ok,"multiple stacks and duplicate cost rows commit atomically")
	check(inventory.snapshot().revision==before.revision+1 and inventory.snapshot().slots[1].count==3 and inventory.snapshot().slots[2].item==0,"one revision and exact remaining contents")
	var blocks=ClassDB.instantiate("NativeBlockWorld")
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new()
	before=inventory.snapshot()
	check(coordinator.place_block(blocks,inventory,Vector3i.ZERO,97) and inventory.snapshot()==before,"default editor places without materials")
	coordinator.gameplay=true
	check(not coordinator.place_block(blocks,inventory,Vector3i(2,0,0),97) and blocks.get_cell(Vector3i(2,0,0))==0,"unaffordable gameplay block creates nothing")
	check(coordinator.place_block(blocks,inventory,Vector3i(2,0,0),1) and inventory.snapshot().slots[1].count==2,"gameplay block consumes one matching material")
	before=inventory.snapshot()
	check(not coordinator.place_block(blocks,inventory,Vector3i(2,0,0),1) and inventory.snapshot()==before,"occupied cell cannot charge twice")
	check(not coordinator.place_block(blocks,inventory,Vector3i(2000000,0,0),1) and inventory.snapshot().slots==before.slots,"native placement rejection restores inventory")
	var prefab=ClassDB.instantiate("NativeBlockPrefab")
	check(prefab.configure(PackedInt32Array([0,0,0,1,1,0,0,34,2,0,0,69,3,0,0,102])) and prefab.get_material_counts()==PackedInt64Array([1,1,1,1]),"native prefab totals cover materials and shapes")
	check(not prefab.configure(PackedInt32Array([0,0,0,128])) and prefab.get_material_counts()==PackedInt64Array([1,1,1,1]),"rejected prefab reconfigure preserves cached costs")
	for item in range(102,105): inventory.grant(item,1,inventory.snapshot().revision)
	before=inventory.snapshot()
	check(not coordinator.place_prefab(blocks,inventory,prefab,Vector3i(2000000,0,0),0) and inventory.snapshot().slots==before.slots,"rejected multi-material prefab refunds every material")
	check(coordinator.place_prefab(blocks,inventory,prefab,Vector3i(10,0,0),0),"gameplay prefab accepted with all materials")
	check(inventory.snapshot().slots[1].count==1 and not inventory.can_afford(PackedInt64Array([102,1]),inventory.snapshot().revision).ok,"prefab debits exact cached totals")
	before=inventory.snapshot()
	check(coordinator.place_block(blocks,inventory,Vector3i(2,0,0),0) and inventory.snapshot()==before,"removal is free without material duplication")
	blocks.free()
	print("CONSTRUCTION_INVENTORY ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
