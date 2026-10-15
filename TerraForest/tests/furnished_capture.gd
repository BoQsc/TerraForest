# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world);world.prepare()
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	catalog.register(world)
	for c in [preload("res://addons/structures/storage_catalog.gd"),preload("res://addons/structures/door_catalog.gd"),preload("res://addons/structures/window_catalog.gd")]:c.register(world)
	var source: Resource=catalog.enclosed_cottage()
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new()
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	var models: Dictionary=world.model_collections()
	check(coordinator.place_prefab(world.blocks,inventory,source,Vector3i(40,40,40),0,models,{},[]),"furnished source placed through combined transaction")
	world.transform=Transform3D(Basis(Vector3.UP,0.7),Vector3(100,5,-80))
	var before: PackedByteArray=world.blocks.capture_snapshot();var snapshots: Dictionary={}
	for key in models:snapshots[key]=models[key].capture_snapshot()
	var library=preload("res://addons/structures/prefab_library.gd").new()
	library.directory="user://tests/furnished_capture_%d"%Time.get_ticks_usec()
	library.select_corner(true,Vector3i(30,38,30));library.select_corner(false,Vector3i(54,57,54))
	var captured: Dictionary=library.capture(world.blocks,"Captured furnished cottage",models.values())
	check(captured.ok,"production library captures furnished selection: "+captured.get("reason",""))
	if captured.ok:
		check(captured.asset.get_model_attachments().size()==13 and captured.asset.get_cell_count()==source.get_cell_count(),"capture retains every window door and furnishing plus exact block count")
		var expected: Dictionary={}
		for item in source.get_model_attachments():
			if not expected.has(item.model):expected[item.model]=[]
			var pose: Transform3D=item.transform;pose.origin+=Vector3(10,2,10);expected[item.model].append(pose)
		var exact:=true
		for item in captured.asset.get_model_attachments():
			var found: int=-1
			for i in expected[item.model].size():
				if item.transform.is_equal_approx(expected[item.model][i]):found=i;break
			if found<0:exact=false
			else:expected[item.model].remove_at(found)
		check(exact,"captured transforms are relative to block selection despite rotated parent")
		var reopened=preload("res://addons/structures/prefab_library.gd").new();reopened.directory=library.directory;reopened.load_library()
		check(reopened.assets.size()==1 and reopened.assets[0].get_model_attachments()==captured.asset.get_model_attachments(),"furnished capture survives library disk reopen exactly")
	check(world.blocks.capture_snapshot()==before,"capture leaves source blocks unchanged")
	for key in models:check(models[key].capture_snapshot()==snapshots[key],"capture leaves source model identities unchanged: "+key)
	# Cut the table across its centre: partial inclusion must not silently omit it.
	library.select_corner(true,Vector3i(39,38,39));library.select_corner(false,Vector3i(54,57,54))
	var partial: Dictionary=library.capture(world.blocks,"Partial objects",models.values())
	check(not partial.ok and "whole object" in partial.reason,"partly selected objects reject incomplete capture")
	library.select_corner(true,Vector3i(30,38,30));library.select_corner(false,Vector3i(54,57,54))
	var table: Node3D=models["furniture/table/v1"]
	var packet: PackedByteArray=table.capture_region(Vector3i(1,1,1))
	check(table.unload_region(packet),"source furniture region retires")
	var unavailable: Dictionary=library.capture(world.blocks,"Unavailable furniture",models.values())
	check(not unavailable.ok and "Load all" in unavailable.reason,"unloaded furniture prevents incomplete prefab publication")
	check(table.restore_region(packet),"source furniture returns exactly")
	world.transform=Transform3D.IDENTITY
	if captured.ok:check(coordinator.place_prefab(world.blocks,inventory,captured.asset,Vector3i(90,40,40),1,models,{},[]),"captured furnished prefab places through normal combined transaction with rotation")
	for file in DirAccess.get_files_at(library.directory):DirAccess.remove_absolute(library.directory.path_join(file))
	DirAccess.remove_absolute(library.directory);world.free()
	print("FURNISHED_CAPTURE failures=",failures);quit(1 if failures else 0)
