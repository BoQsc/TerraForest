# SPDX-License-Identifier: 0BSD
extends SceneTree
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
	inventory.register_item(101,10);inventory.register_item(102,5)
	var before: Dictionary=inventory.snapshot()
	var batch:=PackedInt64Array([101,12,102,6,101,5])
	check(inventory.can_receive(batch,0).ok and inventory.snapshot()==before,"capacity preflight does not mutate")
	check(inventory.grant_items(batch,0).ok,"mixed items and duplicate rows grant atomically")
	var state: Dictionary=inventory.snapshot()
	check(state.revision==1 and state.slots[0].count==10 and state.slots[1].count==7 and state.slots[2].count==5 and state.slots[3].count==1,"deterministic stacking conserves every item with one revision")
	before=state
	check(not inventory.grant_items(batch,0).ok and inventory.snapshot()==before,"replayed revision cannot grant again")
	for invalid in [PackedInt64Array(),PackedInt64Array([101]),PackedInt64Array([101,1,999,1]),PackedInt64Array([101,1,102,0]),PackedInt64Array([101,1,102,-1]),PackedInt64Array([101,9223372036854775807])]:
		check(not inventory.grant_items(invalid,1).ok and inventory.snapshot()==before,"invalid batch cannot partly grant earlier rows")
	var too_many:=PackedInt64Array()
	for i in range(33): too_many.append_array(PackedInt64Array([101,1]))
	check(not inventory.grant_items(too_many,1).ok and inventory.snapshot()==before,"batch row limit enforced")
	# Fill all but one slot; the first batch row would fit, the second would not.
	var full=ClassDB.instantiate("NativePlayerInventory")
	full.register_item(101,1);full.register_item(102,1);full.grant(101,31,0)
	before=full.snapshot()
	var rejected: Dictionary=full.grant_items(PackedInt64Array([101,1,102,1]),before.revision)
	check(not rejected.ok and rejected.reason=="full" and full.snapshot()==before,"late capacity failure leaves earlier grant and revision untouched")
	check(not full.can_receive(PackedInt64Array([101,1,101,1]),before.revision).ok and full.snapshot()==before,"duplicate rows compete for the same remaining capacity")
	check(full.grant_items(PackedInt64Array([102,1]),before.revision).ok,"exact remaining capacity succeeds")
	var maximum=ClassDB.instantiate("NativePlayerInventory");maximum.register_item(101,1000000)
	check(maximum.grant_items(PackedInt64Array([101,32000000]),0).ok,"exact 32-slot maximum accepted")
	before=maximum.snapshot()
	check(not maximum.grant_items(PackedInt64Array([101,1]),before.revision).ok and maximum.snapshot()==before,"full inventory never overflows")
	var packed: PackedByteArray=inventory.capture_storage_snapshot()
	check(inventory.restore_storage_snapshot(packed) and inventory.capture_storage_snapshot()==packed,"multi-grant contents retain existing save compatibility")
	print("INVENTORY_GRANTS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
