# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var rows: Array=[]
const Catalog=preload("res://addons/structures/furniture_catalog.gd")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func fixture() -> Node3D:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	world.prepare();Catalog.register(world);return world
func empty(world: Node) -> bool:
	if world.blocks.stats().cells!=0:return false
	for batch in world.model_collections().values():
		if not batch.get_ids().is_empty():return false
	return true
func prepare(tx: RefCounted) -> Dictionary:
	var result: Dictionary={"ok":true,"status":"preparing"}
	for step in range(1000):
		result=tx.advance(2048,16,1000)
		if not result.ok or result.status!="preparing":return result
	return {"ok":false,"status":"failed"}
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var source: Resource=Catalog.furnished_cottage()
	for count in [4,16,64,128]:
		var world:=fixture();var models: Dictionary=world.model_collections()
		var asset=ClassDB.instantiate("NativeBlockPrefab");asset.compose_frontage([source],count/2,8,3,1703)
		var tx=ClassDB.instantiate("NativePrefabPlacement")
		var start:=Time.get_ticks_usec()
		var result: Dictionary=tx.begin(world.blocks,asset,Vector3i(800,50,800),0,models,[])
		var begin_us:=Time.get_ticks_usec()-start
		var maximum:=0;var steps:=0;var unchanged:=true;var bounded:=true;var previous_cells:=0;var previous_models:=0
		while result.ok and result.status=="preparing" and steps<1000:
			start=Time.get_ticks_usec();result=tx.advance(2048,16,1000);maximum=maxi(maximum,Time.get_ticks_usec()-start);steps+=1
			unchanged=unchanged and empty(world)
			if result.ok:
				bounded=bounded and result.prepared_cells-previous_cells<=2048 and result.prepared_models-previous_models<=16 and result.staged_chunks<=2048
				previous_cells=result.prepared_cells;previous_models=result.prepared_models
		check(result.ok and result.status=="ready" and unchanged and bounded,"bounded preparation leaves live stores unchanged at %d cottages"%count)
		start=Time.get_ticks_usec();result=tx.commit([]);var commit_us:=Time.get_ticks_usec()-start
		var exact: bool=result.ok and world.blocks.stats().cells==count*source.get_cell_count()
		for batch in models.values():exact=exact and batch.get_ids().size()==count
		check(exact,"complete atomic population at %d cottages"%count)
		check(begin_us<=4000 and maximum<=4000 and commit_us<=4000,"all calls <=4ms at %d cottages (begin %d / step %d / commit %d us)"%[count,begin_us,maximum,commit_us])
		rows.append({"cottages":count,"begin_us":begin_us,"max_step_us":maximum,"commit_us":commit_us,"steps":steps,"result":result})
		world.free()
	var world:=fixture();var tx=ClassDB.instantiate("NativePrefabPlacement");var models: Dictionary=world.model_collections()
	var asset: Resource=Catalog.furnished_cottage()
	check(tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[]).ok and not tx.commit([]).ok and empty(world),"premature commit cannot expose partial state")
	check(not tx.begin(world.blocks,asset,Vector3i(70,40,40),0,models,[]).ok,"second begin cannot replace active work")
	check(tx.cancel() and empty(world),"cancel leaves all stores untouched")
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[]);tx.advance(1,1,1000)
	world.blocks.set_cells(PackedInt32Array([1000,40,1000,1]));var saved: PackedByteArray=world.capture_snapshot()
	check(not tx.advance(2048,16,1000).ok and world.capture_snapshot()==saved,"intervening block edit invalidates preparation without losing that edit")
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[])
	asset.configure_model_attachments(asset.get_model_attachments())
	check(not tx.advance(2048,16,1000).ok and world.capture_snapshot()==saved,"changed source invalidates preparation")
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[]);prepare(tx)
	check(not tx.commit([AABB(Vector3(40,40,40),Vector3.ONE)]).ok and world.capture_snapshot()==saved,"actor entering prepared bounds rejects at commit")
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[])
	var table: Node3D=models["furniture/table/v1"]
	table.upsert_instances(PackedInt64Array([9000]),PackedFloat32Array([1,0,0,500,0,1,0,40,0,0,1,500]));saved=world.capture_snapshot()
	check(not tx.advance(2048,16,1000).ok and world.capture_snapshot()==saved,"intervening model edit invalidates preparation")
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	for item in range(101,105):inventory.register_item(item,100000)
	for item in range(101,105):inventory.grant(item,10000,inventory.snapshot().revision)
	var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
	var before: Dictionary=inventory.snapshot()
	check(coordinator.begin_prefab(world.blocks,inventory,asset,Vector3i(40,40,40),0,models,Catalog.recipes(),[]) and inventory.snapshot()==before,"preparation does not debit inventory")
	inventory.grant(102,1,inventory.snapshot().revision);var edited: Dictionary=inventory.snapshot()
	var result: Dictionary
	for frame in range(100):
		result=coordinator.advance_prefab([])
		if not result.ok or result.status!="preparing":break
	check(not result.ok and inventory.snapshot()==edited and world.capture_snapshot()==saved,"inventory change cancels prepared transaction without consuming or overwriting it")
	world.free()
	world=fixture();models=world.model_collections()
	world.blocks.set_cells(PackedInt32Array([47,47,47,1]))
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[])
	check(prepare(tx).ok and tx.commit([]).ok and world.blocks.get_cell(Vector3i(47,47,47))==1,"prepared touched chunk retains unrelated existing cell")
	world.free();world=fixture();models=world.model_collections()
	world.blocks.set_cells(PackedInt32Array([1000,40,1000,1]))
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[]);prepare(tx)
	world.blocks.set_cells(PackedInt32Array([1000,40,1000,0]))
	check(not tx.commit([]).ok and empty(world),"last-cell deletion invalidates ready publication")
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[])
	models["furniture/table/v1"].free()
	check(not tx.advance(2048,16,1000).ok and world.blocks.stats().cells==0,"deleted model collection cancels safely")
	world.free();world=fixture();models=world.model_collections()
	tx.begin(world.blocks,asset,Vector3i(40,40,40),0,models,[]);prepare(tx)
	world.free()
	check(not tx.commit([]).ok,"deleted block world rejects publication safely")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:={"checks":checks,"failures":failures,"rows":rows,"scope":"One headless call-level sample per population; no rendering, terrain, dense pre-existing model population or sustained frame-time claim. Preparation target 1ms, at most2048 cells/16 models per call; admission/publication gate4ms."}
	var file:=FileAccess.open("res://reports/prefab_staged.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(1 if failures else 0)
