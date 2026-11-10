# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var catalog=preload("res://addons/player_runtime/item_catalog.gd")
	var placement=load("res://addons/player_runtime/object_placement.gd")
	var inventory:RefCounted=catalog.create_inventory()
	for item:int in catalog.Objects.ITEMS:
		check(inventory.grant(item,1,inventory.snapshot().revision).ok,"carried object registered: "+catalog.item_name(item))
		check(catalog.matches(item,"object") and preload("res://addons/player_runtime/item_icons.gd").texture(item)!=null,"object searchable with existing model icon")
	var restored:RefCounted=catalog.create_inventory()
	check(restored.restore_storage_snapshot(inventory.capture_storage_snapshot()),"carried objects round-trip through existing inventory format")
	var legacy:RefCounted=catalog.create_inventory();legacy.grant(1,1,legacy.snapshot().revision)
	check(restored.restore_storage_snapshot(legacy.capture_storage_snapshot()),"ordinary older item-only snapshot still loads")
	var barrel:=AABB(Vector3(-.36,-.5,-.36),Vector3(.72,1.05,.72))
	check(placement.occupied_cells(barrel)==[Vector3i(0,0,0),Vector3i(0,1,0)],"barrel highlights both occupied building cells")
	check(placement.occupied_cells(AABB(Vector3(-.5,-.5,-.5),Vector3.ONE))==[Vector3i.ZERO],"exact grid boundaries do not include adjacent cells")
	check(placement.occupied_cells(AABB(Vector3.ZERO,Vector3.ONE*100)).is_empty(),"preview generation is bounded")
	var collection=ClassDB.instantiate("NativeStaticBatch");root.add_child(collection)
	check(collection.configure_asset("tests/carried_chair",BoxMesh.new()),"existing native model owner initialized")
	var history=ClassDB.instantiate("NativeStaticHistory");history.configure([collection],1048576,256)
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
	var pose:=PackedFloat32Array([1,0,0,10,0,1,0,0,0,0,1,0])
	var id:int=coordinator.place_model(history,collection,inventory,pose,AABB(),PackedInt64Array([702,1]))
	check(id>0,"carried chair creates a persistent native model")
	var before:Dictionary=inventory.snapshot()
	check(coordinator.place_model(history,collection,inventory,pose,AABB(),PackedInt64Array([702,1]))==0 and inventory.snapshot()==before,"repeated click cannot place an unpaid chair")
	check(load("res://demo/world.gd")!=null and load("res://addons/player_runtime/player_hud.gd")!=null,"world and carried-item integration compile")
	collection.free();await process_frame
	print("CARRIED_OBJECTS failures=",failures);quit(1 if failures else 0)
