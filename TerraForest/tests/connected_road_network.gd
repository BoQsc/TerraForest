extends SceneTree
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Adapter=preload("res://addons/world_runtime/road_normalization.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Audit=preload("res://tests/road_grid_network_audit.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func run()->void:
	var folder:="res://reports/connected_roads";DirAccess.make_dir_recursive_absolute(folder)
	var results:Array=[]
	for seed_value in [1703,42,9137]:
		var options:Dictionary=Recipe.DEFAULTS.duplicate();options.road_grid=0
		var plan:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		check(plan.get("ok",false),"original planning available "+str(seed_value))
		if not plan.get("ok",false):continue
		var roads:Array=[]
		for site:Dictionary in plan.sites:roads.append_array(site.roads)
		for road:Dictionary in plan.network.segments:
			if int(road.material)==4:roads.append(road)
		var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,23]))
		var fitted:Dictionary=core.fit_road_network(roads,Adapter.protected_areas(plan.sites))
		check(fitted.get("ok",false) or fitted.get("reason","").begins_with("Corridor requires rerouting"),"native connected grades solve or explicitly demand rerouting "+str(seed_value))
		if fitted.get("ok",false):
			check(fitted.contact_after>=fitted.contact_before,"network contact objective improves without changing targeting")
			check(fitted==core.fit_road_network(roads,Adapter.protected_areas(plan.sites)),"connected solve deterministic")
			FileAccess.open(folder.path_join("plan_%d.bin"%seed_value),FileAccess.WRITE).store_var({"original":roads,"fitted":fitted,"plan":plan})
			if seed_value==1703:
				var found:Dictionary={};var point:=Vector2(1076.823,838.3824)
				for road:Dictionary in fitted.segments:
					var start:=Vector2(road.start.x,road.start.z);var axis:=Vector2(road.finish.x-road.start.x,road.finish.z-road.start.z)
					var fraction:float=(point-start).dot(axis)/axis.length_squared()
					if fraction<0 or fraction>1 or absf((point-start).cross(axis))/axis.length()>2:continue
					var height:=lerpf(road.start.y,road.finish.y,fraction)
					if road.has("coefficients"):
						var curve:PackedFloat64Array=road.coefficients;var offset:int=int(road.curve_index)*4
						height=((curve[offset]*fraction+curve[offset+1])*fraction+curve[offset+2])*fraction+curve[offset+3]
					found={"height":height,"road":road}
				FileAccess.open(folder.path_join("saved_case.json"),FileAccess.WRITE).store_string(JSON.stringify(found,"  "));print("SAVED_CASE ",found)
		var report:=fitted.duplicate();report.erase("segments");report["seed"]=seed_value;results.append(report);print("CONNECTED_ROAD ",report)
		options.road_grid=2
		var started:=Time.get_ticks_usec()
		var complete:=Plan.build(seed_value,23,options,folder.path_join("plans"))
		report["planning_ms"]=(Time.get_ticks_usec()-started)/1000.0
		check(complete.get("ok",false),"production planner fits or reroutes connected network "+str(seed_value))
		print("CONNECTED_PRODUCTION ",seed_value," ",complete.get("reason",complete.get("road_normalization",{})))
		if complete.get("ok",false):
			FileAccess.open(folder.path_join("complete_%d.bin"%seed_value),FileAccess.WRITE).store_var(complete)
			report["production"]=complete.road_normalization
			var preserved:=true
			for site_index in plan.sites.size():
				preserved=preserved and complete.sites[site_index].block_paving.records==plan.sites[site_index].block_paving.records
				for lot_index in plan.sites[site_index].lots.size():preserved=preserved and complete.sites[site_index].lots[lot_index].origin==plan.sites[site_index].lots[lot_index].origin
			check(preserved,"trusted house origins and plate cells remain exact")
			var before:=Audit.coverage(Audit.roads_for(plan))
			var after:=Audit.coverage(Audit.roads_for(complete),before.cells)
			var fresh:=Audit.coverage(Audit.roads_for(complete))
			var covered_before:=0;var covered_after:=0;var bad_before:=0;var bad_after:=0
			for category:Dictionary in before.categories.values():covered_before+=category.sampled_cells;bad_before+=category.unfit_cells
			for category:Dictionary in after.categories.values():covered_after+=category.sampled_cells;bad_after+=category.unfit_cells
			report["coverage"]={"before":before.categories,"after":after.categories,"same_coordinates":true,"covered_before":covered_before,"covered_after":covered_after,"unfit_before":bad_before,"unfit_after":bad_after}
			report.coverage["new_corridor_samples"]=fresh.categories
			check(bad_after<float(bad_before)*covered_after/maxi(1,covered_before),"independent grid footprint coverage improves "+str(seed_value))
			if seed_value==1703:
				options.road_grid=1
				var legacy:=Plan.build(seed_value,23,options,folder.path_join("plans"))
				check(legacy.get("ok",false),"legacy normalization still loads unchanged")
				if legacy.get("ok",false):report.coverage["legacy"]=Audit.coverage(Audit.roads_for(legacy),before.cells).categories
			print("CONNECTED_COVERAGE ",seed_value," ",report.coverage)
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"results":results},"  "))
	print("CONNECTED_ROAD_NETWORK failures=",failures);quit(1 if failures else 0)
