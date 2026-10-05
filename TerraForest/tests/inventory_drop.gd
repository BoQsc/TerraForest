# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var hud=load("res://addons/player_runtime/player_hud.gd").new()
	hud.gameplay_construction=true
	hud.prepare()
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	var pickups=load("res://addons/world_runtime/material_pickups.gd").new()
	root.add_child(pickups)
	check(pickups.prepare(persistence),"native pickup stores ready")
	var inventory: RefCounted=hud.inventory
	var before: Dictionary=inventory.snapshot()
	var slot:=4
	check(before.slots[slot].item==101,"fixture selects brick inventory slot")
	var observations: Array=[]
	pickups.changed.connect(func():
		observations.append([inventory.snapshot().slots[slot].count,pickups.stores[101].statistics().active])
		check(not pickups.drop_one(inventory,slot,inventory.snapshot().revision,Vector3.ZERO).ok,"reentrant drop is refused"),CONNECT_ONE_SHOT)
	var result: Dictionary=pickups.drop_one(inventory,slot,before.revision,Vector3(1,2,3))
	check(result.ok and inventory.snapshot().slots[slot].count==63,"drop consumes exactly one selected material")
	check(observations==[[63,1]],"change observers see inventory and world committed together")
	var store: RefCounted=pickups.stores[101]
	check(store.get_position(store.resolve_identity(result.id))==Vector3(1,2,3),"drop retains exact local position and persistent identity")
	check(not pickups.drop_one(inventory,slot,before.revision,Vector3.ZERO).ok,"stale selection cannot drop again")
	var saved_inventory: PackedByteArray=inventory.capture_storage_snapshot()
	for args in [[-1,Vector3.ZERO],[32,Vector3.ZERO],[0,Vector3.ZERO],[slot,Vector3(NAN,0,0)]]:
		check(not pickups.drop_one(inventory,args[0],inventory.snapshot().revision,args[1]).ok,"invalid slot/tool/position rejected")
	check(inventory.capture_storage_snapshot()==saved_inventory and store.statistics().active==1,"rejections preserve both sides")
	var saved_pickups: PackedByteArray=store.capture_storage_snapshot()
	var restored: RefCounted=ClassDB.instantiate("NativeEntityStore");restored.configure(4096)
	check(restored.restore_storage_snapshot(saved_pickups) and restored.resolve_identity(result.id)>0,"dropped supply survives native snapshot round trip")
	var collected: Dictionary=pickups.collect_near(Vector3(1,2,3),inventory,func(_p: Vector3): return true)
	check(collected.ok and inventory.snapshot().slots[slot].count==64 and store.statistics().active==0,"recollection conserves supply count")
	var legacy: Dictionary=persistence._capture().sections
	for item in [201,202,203]:
		legacy.erase("pickups_%d"%item)
		pickups.spawn(item,Vector3.ZERO)
	persistence._restore(legacy,1)
	check(pickups.stores[201].statistics().active==0 and pickups.stores[202].statistics().active==0 and pickups.stores[203].statistics().active==0,"legacy sections restore absent resource pickups to empty defaults")
	for i in range(4096): store.spawn(Vector3(i,0,0),Vector3.ZERO)
	var revision: int=inventory.snapshot().revision
	saved_inventory=inventory.capture_storage_snapshot()
	check(not pickups.drop_one(inventory,slot,revision,Vector3.ZERO).ok,"full native world store rejects drop")
	check(inventory.snapshot().revision==revision and inventory.capture_storage_snapshot()==saved_inventory and store.statistics().active==4096,"capacity rejection leaves inventory revision and contents unchanged")
	hud.free();pickups.free()
	print("INVENTORY_DROP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
