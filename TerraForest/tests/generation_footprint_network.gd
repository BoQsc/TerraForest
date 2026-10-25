extends SceneTree
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Audit=preload("res://tests/road_grid_network_audit.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func support_roads(plan:Dictionary)->Array:
	var result:Array=[]
	for site:Dictionary in plan.sites:
		for road:Dictionary in site.roads:
			var copy:=road.duplicate();copy.half_width=5.5;copy["category"]="settlement_support";result.append(copy)
	for road:Dictionary in plan.network.segments:
		if int(road.material)!=1:continue
		var copy:=road.duplicate();copy["category"]="regional_support";result.append(copy)
	return result
func count_unfit(coverage:Dictionary)->int:
	var total:=0
	for group:Dictionary in coverage.categories.values():total+=int(group.unfit_cells)
	return total
func run()->void:
	var folder:="res://reports/generation_contact_native";DirAccess.make_dir_recursive_absolute(folder)
	var results:Array=[]
	for seed_value in [1703,42,9137]:
		var options:Dictionary=Recipe.DEFAULTS.duplicate();options.road_grid=2
		var before:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		options.road_grid=3
		check(Recipe.encode(options).decode_u32(4)==4,"footprint generation has distinct durable recipe")
		var after:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		check(before.get("ok",false) and after.get("ok",false),"both native planning recipes succeed "+str(seed_value))
		if not before.get("ok",false) or not after.get("ok",false):print("FOOTPRINT_FAILURE ",after);continue
		var baseline:=Audit.coverage(support_roads(before),{},true);var revised:=Audit.coverage(support_roads(after),baseline.cells,true)
		var fresh:=Audit.coverage(support_roads(after),{},true)
		var previous_bad:=count_unfit(baseline);var current_bad:=count_unfit(revised)
		var previous_count:=0;var revised_count:=0
		for category:Dictionary in baseline.categories.values():previous_count+=category.sampled_cells
		for category:Dictionary in revised.categories.values():revised_count+=category.sampled_cells
		check(previous_count==revised_count and current_bad<previous_bad,"identical full-support footprints improve over the current default")
		var preserved:=true
		for site_index in before.sites.size():
			preserved=preserved and before.sites[site_index].block_paving.records==after.sites[site_index].block_paving.records
			for lot_index in before.sites[site_index].lots.size():preserved=preserved and before.sites[site_index].lots[lot_index].origin==after.sites[site_index].lots[lot_index].origin
		check(preserved,"approved house origins and plate cells stay exact")
		var warm:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		check(warm.get("cache_hit",false) and warm.get("plan_digest","")==after.plan_digest and warm.road_normalization==after.road_normalization,"binary cached plan bypasses generation without changing grades")
		var report:={"seed":seed_value,"before_ms":before.worker_ms,"after_ms":after.worker_ms,"before_cache":before.cache_hit,"after_cache":after.cache_hit,"before":baseline.categories,"after":revised.categories,"fresh":fresh.categories,"before_unfit":previous_bad,"after_unfit":current_bad,"policy":after.road_normalization}
		report["cached_ms"]=warm.worker_ms;report["cache_hit"]=warm.get("cache_hit",false)
		if seed_value==1703:
			var spot:=Audit.coverage(support_roads(after),{Vector2i(953,1137):{}},true)
			report["shoulder"]=spot.cells[Vector2i(953,1137)]
			report["regional"]=Audit.coverage(support_roads(after),{Vector2i(1076,838):{}},true).cells[Vector2i(1076,838)]
		FileAccess.open(folder.path_join("plan_%d.bin"%seed_value),FileAccess.WRITE).store_var(after)
		results.append(report);print("FOOTPRINT_NETWORK ",JSON.stringify(report))
	FileAccess.open(folder.path_join("network.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"results":results},"  "))
	print("GENERATION_FOOTPRINT_NETWORK failures=",failures);quit(1 if failures else 0)
