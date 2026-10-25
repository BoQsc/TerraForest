extends SceneTree
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Works=preload("res://addons/world_runtime/generation_earthworks.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var folder:="res://reports/road_normalization"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var codec:=Recipe.codec()
	var options:Dictionary=Recipe.DEFAULTS.duplicate()
	check(options.road_grid==2,"new roads default to connected grid planning")
	options.road_grid=1
	var bytes:=Recipe.encode(options)
	check(bytes.size()==32 and bytes.decode_u32(4)==2 and codec.decode(bytes)==options,"version-two binary recipe roundtrip")
	var legacy:=options.duplicate();legacy.erase("road_grid")
	check(Recipe.encode(legacy).size()==28 and not codec.decode(Recipe.encode(legacy)).has("road_grid"),"legacy bytes do not opt old worlds into new grading")
	var off:=options.duplicate();off.road_grid=0
	check(Recipe.encode(off)!=bytes,"road option has independent cache and persistence identity")
	var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
	check(browser.buildable_ground.button_pressed and browser.buildable_roads.button_pressed,"both separate creation controls default on")
	var identity:String=browser.selected_preview_key();browser.buildable_roads.button_pressed=false
	check(browser.selected_preview_key()!=identity and browser.buildable_ground.button_pressed,"road toggle does not alter terrain preference")
	browser.buildable_roads.button_pressed=true;browser.buildable_ground.button_pressed=false
	check(browser.selected_preview_key()!=identity and browser.buildable_roads.button_pressed,"terrain toggle does not alter road preference")
	browser.free();await process_frame
	var results:Array=[]
	for seed_value in [1703,42,9137]:
		var before:=Plan.build(seed_value,23,off,folder.path_join("plans"))
		var after:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		check(before.get("ok",false) and after.get("ok",false),"both modes fit seed %d"%seed_value)
		if not before.get("ok",false) or not after.get("ok",false):print(before.get("reason"),after.get("reason"));continue
		var stats:Dictionary=after.road_normalization
		check(stats.enabled and stats.max_shift<=.55001 and stats.max_cut<=3.00001 and stats.max_fill<=2.00001,"changed corridors stay within displacement and full-width earthwork budgets")
		var preserved:=true
		for site_index in before.sites.size():
			var old_site:Dictionary=before.sites[site_index];var new_site:Dictionary=after.sites[site_index]
			preserved=preserved and old_site.block_paving.records==new_site.block_paving.records
			for lot_index in old_site.lots.size():
				preserved=preserved and old_site.lots[lot_index].origin==new_site.lots[lot_index].origin and old_site.lots[lot_index].entrance==new_site.lots[lot_index].entrance
		check(preserved,"approved buildings, entrances and exact trusted plate records stay unchanged")
		check(before.plan_digest!=after.plan_digest and Plan.build(seed_value,23,options,folder.path_join("plans")).plan_digest==after.plan_digest,"off/on plans differ and normalized cache reopens exactly")
		var report:={"seed":seed_value,"original_stamps":before.works.segments.size(),"normalized_stamps":after.works.segments.size(),"normalization":stats,"cold_ms":after.worker_ms}
		results.append(report);print("NORMALIZATION ",JSON.stringify(report))
		if seed_value!=1703:continue
		var old_road:Dictionary={}
		for road:Dictionary in before.market.roads:
			if Vector2(road.start.x,road.start.z).distance_to(Vector2(1003.667,1093))<.01:old_road=road;break
		check(not old_road.is_empty(),"same horizontal road location is present after terrain normalization")
		var selected:Array=[]
		if not old_road.is_empty():
			for road:Dictionary in after.market.roads:
				if absf(road.start.z-1093)<.01 and road.start.x>=old_road.start.x-.001 and road.finish.x<=old_road.finish.x+.001 and road.finish.x>road.start.x:selected.append(road)
		check(not selected.is_empty(),"same road is present in normalized master plan")
		FileAccess.open(folder.path_join("selected.bin"),FileAccess.WRITE).store_var({"road":old_road,"segments":selected,"stats":stats})
		FileAccess.open(folder.path_join("selected.json"),FileAccess.WRITE).store_string(JSON.stringify({"road":old_road,"segments":selected,"protected":preload("res://addons/world_runtime/road_normalization.gd").protected_areas(after.sites)},"  "))
		var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,23]))
		check(core.bake_generated_earthworks(Works.packets(selected)).get("ok",false),"production-selected road bakes normally")
		var snapshot:PackedByteArray=core.execute(Codec.command(4)).slice(12)
		var restored:RefCounted=ClassDB.instantiate("TerrainCore");var restore:=Codec.command(5);restore.append_array(snapshot)
		check(Codec.reply_ok(restored.execute(restore)) and restored.execute(Codec.command(4)).slice(12)==snapshot,"generated terrain retains exact binary snapshot")
		check(not core.normalize_roads([{}],[]).get("ok",false),"invalid normalization descriptor fails explicitly")
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":results},"  "))
	print("ROAD_NORMALIZATION failures=",failures)
	quit(1 if failures else 0)
