# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"structure world ready")
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	check(catalog.register(world).size()==3,"furniture collections registered")
	check(not preload("res://addons/structures/storage_catalog.gd").register(world).is_empty(),"chest collection registered")
	var asset: Resource=catalog.furnished_cottage(true)
	check(not world.blocks.place_prefab(asset,Vector3i(40,40,40),0),"block-only API refuses to discard attached models")
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new()
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	for item in range(101,105):inventory.register_item(item,100000)
	for item in range(101,105):inventory.grant(item,10000,inventory.snapshot().revision)
	world.blocks.configure_history(4096,8)
	world.blocks.set_cells(PackedInt32Array([1000,40,1000,1]))
	check(world.blocks.history_stats().undo_steps==1,"prior block edit is undoable before combined placement")
	var models: Dictionary=world.model_collections()
	var before: Dictionary=inventory.snapshot()
	var blocks_before: PackedByteArray=world.blocks.capture_snapshot()
	coordinator.gameplay=true
	check(not coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(40,40,40),0,{},preload("res://addons/structures/construction_catalog.gd").recipes(),[]) and inventory.snapshot().slots==before.slots and world.blocks.capture_snapshot()==blocks_before,"missing model refunds every cost without block insertion")
	var revisions: Dictionary={}
	for key: String in models: revisions[key]=models[key].capture_snapshot()
	check(not coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(40,40,40),0,models,preload("res://addons/structures/construction_catalog.gd").recipes(),[AABB(Vector3(40,40,40),Vector3.ONE)]) and inventory.snapshot().slots==before.slots and world.blocks.capture_snapshot()==blocks_before,"protected player rejects complete transaction and refunds")
	var exact_models:=true
	for key: String in models:exact_models=exact_models and models[key].capture_snapshot()==revisions[key]
	check(exact_models,"rejected transactions preserve every model store")
	var observed: Array=[]
	world.blocks.changed.connect(func():
		observed.append(models["furniture/table/v1"].get_ids().size()==1 and models["furniture/chair/v1"].get_ids().size()==1 and models["furniture/shelf/v1"].get_ids().size()==1 and models["storage/wooden_chest/v1"].get_ids().size()==1),CONNECT_ONE_SHOT)
	check(coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(40,40,40),0,models,preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"paid furnished cottage places: "+coordinator.reason)
	check(world.blocks.history_stats().undo_steps==0 and world.blocks.history_stats().redo_steps==0,"combined placement establishes block-history barrier")
	check(observed==[true],"block publication observes every committed model")
	var expected=ClassDB.instantiate("NativePlayerInventory")
	for item in range(101,105):expected.register_item(item,100000)
	expected.restore(before,0)
	var costs:=PackedInt64Array();var counts: PackedInt64Array=asset.get_material_counts()
	for material in range(4):
		if counts[material]>0:costs.append_array(PackedInt64Array([101+material,counts[material]]))
	costs.append_array(PackedInt64Array([102,25]));expected.consume_items(costs,expected.snapshot().revision)
	check(expected.snapshot().slots==inventory.snapshot().slots,"exact block materials plus 25 furniture and chest wood deducted")
	var contents: RefCounted=ClassDB.instantiate("NativeContainerStore");contents.configure(inventory,4096)
	var first_id: int=models["storage/wooden_chest/v1"].get_ids()[0]
	var wood_slot:=-1
	for i in 32:
		if inventory.snapshot().slots[i].item==102:wood_slot=i
	check(contents.deposit(first_id,inventory,wood_slot,1,inventory.snapshot().revision,0).ok,"first furnished chest accepts its own inventory")
	var saved: PackedByteArray=world.capture_snapshot()
	before=inventory.snapshot()
	check(not coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(40,40,40),0,models,preload("res://addons/structures/construction_catalog.gd").recipes(),[]) and inventory.snapshot().slots==before.slots and world.capture_snapshot()==saved,"repeated placement is rejected without partial changes")
	before=inventory.snapshot()
	coordinator.gameplay=false
	for turn in range(1,4):check(coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(40+turn*30,40,40),turn,models,{},[]),"editor rotated furnished cottage %d: %s"%[turn,coordinator.reason])
	check(inventory.snapshot()==before,"editor furnished placement is free")
	for key: String in models:check(models[key].get_ids().size()==4,"four placed objects for "+key)
	var independent:=true
	for id in models["storage/wooden_chest/v1"].get_ids():
		independent=independent and contents.has_contents(id)==(id==first_id)
	check(independent and contents.get_ids().size()==1,"repeated furnished buildings create empty independent chests without copying contents")
	coordinator.gameplay=true
	check(coordinator.begin_prefab(world.blocks,inventory,asset,Vector3i(350,40,40),0,models,preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"staged paid storage prefab begins")
	var prepared: Dictionary={}
	for step in 1000:
		prepared=coordinator.advance_prefab([])
		if not prepared.ok or prepared.status!="preparing":break
	check(prepared.get("ok",false) and models["storage/wooden_chest/v1"].get_ids().size()==5,"staged paid storage prefab commits complete chest and blocks")
	coordinator.gameplay=false
	var invalid: Resource=catalog.furnished_cottage(true)
	var invalid_items: Array=invalid.get_model_attachments()
	invalid_items[0].transform.origin=Vector3(200,1,0);invalid.configure_model_attachments(invalid_items)
	var retained: PackedByteArray=world.capture_snapshot()
	check(not coordinator.place_prefab(world.blocks,inventory,invalid,Vector3i(200,40,40),0,models,{},[]) and world.capture_snapshot()==retained,"attachment outside surveyed envelope rejects without changes")
	invalid_items[0].transform.origin=Vector3(-4,1,0);invalid.configure_model_attachments(invalid_items)
	for turn in range(4):
		check(not coordinator.place_prefab(world.blocks,inventory,invalid,Vector3i(200,40,40),turn,models,{},[]) and world.capture_snapshot()==retained,"attachment through rotated prefab wall rejects without changes %d"%turn)
	var table: Node3D=models["furniture/table/v1"]
	table.upsert_instances(PackedInt64Array([9223372036854775807]),PackedFloat32Array([1,0,0,500,0,1,0,40,0,0,1,500]))
	retained=world.capture_snapshot()
	check(not coordinator.place_prefab(world.blocks,inventory,asset,Vector3i(200,40,40),0,models,{},[]) and world.capture_snapshot()==retained,"exhausted collection identity rejects all stores")
	table.remove_instances(PackedInt64Array([9223372036854775807]))
	var restored=preload("res://addons/structures/structures_world.gd").new();root.add_child(restored)
	restored.prepare();catalog.register(restored);preload("res://addons/structures/storage_catalog.gd").register(restored)
	var snapshot: PackedByteArray=world.capture_snapshot()
	check(restored.restore_snapshot(snapshot) and restored.capture_snapshot()==snapshot,"combined block and furniture snapshot round trip")
	restored.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output:=FileAccess.open("res://reports/storage_prefab.json",FileAccess.WRITE);output.store_string(JSON.stringify({"checks":checks,"failures":failures}));output.close()
	world.free();print("STORAGE_PREFAB checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
