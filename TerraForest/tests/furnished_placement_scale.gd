# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var rows: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	var source: Resource=catalog.furnished_cottage()
	var transaction=ClassDB.instantiate("NativePrefabPlacement")
	for count in [4,16,64,128]:
		var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
		check(world.prepare() and catalog.register(world).size()==3,"prepare fixture %d"%count)
		var asset=ClassDB.instantiate("NativeBlockPrefab")
		var start:=Time.get_ticks_usec()
		check(asset.compose_frontage([source],count/2,8,3,1703),"compose %d furnished cottages"%count)
		var compose_us:=Time.get_ticks_usec()-start
		var models: Dictionary=world.model_collections()
		start=Time.get_ticks_usec()
		var result: Dictionary=transaction.place(world.blocks,asset,Vector3i(800,50,800),0,models,[])
		var place_us:=Time.get_ticks_usec()-start
		check(result.get("ok",false),"place %d cottages: %s"%[count,result.get("reason","")])
		var exact: bool=world.blocks.stats().cells==count*source.get_cell_count()
		for collection in models.values():exact=exact and collection.get_ids().size()==count
		check(exact,"exact block and furniture population %d"%count)
		check(place_us<=4000,"synchronous placement <=4ms at %d cottages (%dus)"%[count,place_us])
		rows.append({"cottages":count,"blocks":world.blocks.stats().cells,"models":count*3,"compose_us":compose_us,"place_us":place_us,"result":result})
		world.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:={"failures":failures,"budget_us":4000,"scope":"One cold synchronous native placement per size in an empty structure world. Native validation and commit only; no rendering, terrain, inventory, steady-state, thermal or 60 FPS claim.","rows":rows}
	var file:=FileAccess.open("res://reports/furnished_placement_scale.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(1 if failures else 0)
