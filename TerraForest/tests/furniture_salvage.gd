# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world);world.prepare()
	preload("res://addons/structures/furniture_catalog.gd").register(world)
	var shelf: Node3D=world.model("furniture/shelf/v1")
	var inventory: RefCounted=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(102,10)
	var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([shelf],1048576,32)
	var pose:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])
	var id: int=history.insert(shelf,pose,AABB())
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
	var rewards: PackedInt64Array=preload("res://addons/structures/furniture_catalog.gd").salvage_recipes()["furniture/shelf/v1"]
	inventory.grant(102,320,0)
	var before: Dictionary=inventory.snapshot();var geometry: PackedByteArray=shelf.capture_snapshot()
	check(not coordinator.salvage_model(history,shelf,inventory,id,rewards) and inventory.snapshot()==before and shelf.capture_snapshot()==geometry,"full inventory retains shelf and every item")
	inventory.consume(0,3,inventory.snapshot().revision);before=inventory.snapshot()
	check(not coordinator.salvage_model(history,shelf,inventory,id,rewards) and inventory.snapshot()==before and shelf.capture_snapshot()==geometry,"partial space cannot consume object for partial reward")
	inventory.consume(0,1,inventory.snapshot().revision);before=inventory.snapshot()
	shelf.set_removal_protected(id,true)
	check(not coordinator.salvage_model(history,shelf,inventory,id,rewards) and inventory.snapshot()==before,"protected object cannot yield salvage")
	shelf.set_removal_protected(id,false)
	var observed: Array=[]
	shelf.changed.connect(func():observed.append(inventory.snapshot().slots[0].count==10),CONNECT_ONE_SHOT)
	check(coordinator.salvage_model(history,shelf,inventory,id,rewards),"shelf dismantles with exact capacity available")
	check(shelf.get_ids().is_empty() and inventory.snapshot().slots[0].count==10 and observed==[true],"four wood visible before removal publication")
	before=inventory.snapshot()
	check(not history.undo(AABB()) and not history.redo(AABB()),"salvage cannot be undone to duplicate resources")
	check(not coordinator.salvage_model(history,shelf,inventory,id,rewards) and inventory.snapshot()==before,"repeated salvage of deleted ID yields nothing")
	id=history.insert(shelf,pose,AABB());coordinator.gameplay=false
	check(not coordinator.salvage_model(history,shelf,inventory,id,rewards) and shelf.get_ids().size()==1 and inventory.snapshot()==before,"free editor does not grant gameplay rewards")
	world.free();await process_frame
	print("FURNITURE_SALVAGE ",JSON.stringify({"checks":checks,"failures":failures}));quit(1 if failures else 0)
