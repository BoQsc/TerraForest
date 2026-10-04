# SPDX-License-Identifier: 0BSD
extends SceneTree
const Crafting=preload("res://addons/player_runtime/crafting.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	for item in [101,103,104,201,202,203]: inventory.register_item(item,10)
	inventory.grant(201,320,0)
	var before: Dictionary=inventory.snapshot()
	check(not Crafting.craft(inventory,0,1,before.revision).ok and inventory.snapshot()==before,"full output capacity preserves inputs and revision")
	check(inventory.exchange_items(PackedInt64Array([201,10]),PackedInt64Array([101,1]),before.revision).ok,"consumed input slot can hold crafted output")
	check(inventory.snapshot().revision==before.revision+1 and inventory.snapshot().slots[0].item==101,"exchange publishes one revision")
	before=inventory.snapshot()
	for outputs in [PackedInt64Array(),PackedInt64Array([999,1]),PackedInt64Array([101,1,104,-1]),PackedInt64Array([101,32000001])]:
		check(not inventory.exchange_items(PackedInt64Array([201,10]),outputs,before.revision).ok and inventory.snapshot()==before,"invalid outputs cannot consume inputs")
	check(not inventory.exchange_items(PackedInt64Array([201,1000]),PackedInt64Array([101,1]),before.revision).ok and inventory.snapshot()==before,"insufficient ingredients change nothing")
	check(not Crafting.craft(inventory,0,1,before.revision-1).ok and inventory.snapshot()==before,"stale craft cannot replay")
	check(not Crafting.craft(inventory,4,1,before.revision).ok and not Crafting.craft(inventory,0,1001,before.revision).ok and inventory.snapshot()==before,"recipe and batch bounds enforced")
	var fresh=ClassDB.instantiate("NativePlayerInventory")
	for item in [101,103,104,201,202,203]: fresh.register_item(item,999)
	fresh.grant_items(PackedInt64Array([201,5,202,2,203,2]),0)
	for recipe in range(4): check(Crafting.craft(fresh,recipe,1,fresh.snapshot().revision).ok,"starter recipe %d succeeds"%recipe)
	check(not fresh.can_afford(PackedInt64Array([201,1]),fresh.snapshot().revision).ok and fresh.can_afford(PackedInt64Array([101,1,103,1,104,2]),fresh.snapshot().revision).ok,"recipes conserve specified inputs and outputs")
	print("INVENTORY_CRAFTING ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
