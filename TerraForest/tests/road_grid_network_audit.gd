extends SceneTree
const Plan=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const GapLimit:=.10
const BurialLimit:=.25
var game:Node
var failures:=0
var evidence:="res://reports/grid_network_audit"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func wait_for(predicate:Callable,seconds:int=90)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func profile_height(road:Dictionary,point:Vector2)->float:
	var start:Vector3=road.start;var finish:Vector3=road.finish
	var axis:=Vector2(finish.x-start.x,finish.z-start.z)
	var fraction:=Vector2(point.x-start.x,point.y-start.z).dot(axis)/axis.length_squared()
	if not road.has("coefficients"):return lerpf(start.y,finish.y,fraction)
	var curve:PackedFloat64Array=road.coefficients;var offset:int=int(road.curve_index)*4
	return ((curve[offset]*fraction+curve[offset+1])*fraction+curve[offset+2])*fraction+curve[offset+3]
func contact(minimum:float,maximum:float)->Dictionary:
	var lowest:=ceili(maximum-BurialLimit-.00001)
	var highest:=floori(minimum+GapLimit+.00001)
	var best:Dictionary={};var best_cost:=INF
	for bottom in range(floori(minimum)-1,ceili(maximum)+2):
		var gap:=maxf(0,bottom-minimum);var burial:=maxf(0,maximum-bottom)
		var cost:=maxf(0,gap-GapLimit)+maxf(0,burial-BurialLimit)
		if cost<best_cost:best_cost=cost;best={"bottom":bottom,"gap":gap,"burial":burial}
	return {"fits_any_integer_cell":lowest<=highest,"minimum":minimum,"maximum":maximum,"best":best}
func roads_for(plan:Dictionary)->Array:
	var result:Array=[]
	for site:Dictionary in plan.sites:
		for road:Dictionary in site.roads:
			var record:=road.duplicate();record["category"]="settlement";result.append(record)
	for road:Dictionary in plan.network.segments:
		if int(road.material)!=4:continue
		var record:=road.duplicate();record["category"]="regional";result.append(record)
	return result
func coverage(roads:Array,queries:Dictionary={})->Dictionary:
	var cells:Dictionary=queries.duplicate(true)
	var categories:Dictionary={}
	var worst:Array=[]
	var segments:=0
	for road:Dictionary in roads:
		var start:=Vector2(road.start.x,road.start.z);var finish:=Vector2(road.finish.x,road.finish.z)
		var axis:Vector2=finish-start;var length:=axis.length();var width:float=road.half_width
		if length<2:continue
		segments+=1
		if not categories.has(road.category):categories[road.category]={"segments":0,"sampled_cells":0,"unfit_cells":0,"fractional_endpoints":0}
		categories[road.category].segments+=1
		for point:Vector3 in [road.start,road.finish]:
			if not contact(point.y,point.y).fits_any_integer_cell:categories[road.category].fractional_endpoints+=1
		if not queries.is_empty():continue
		var side:=Vector2(-axis.y,axis.x)/length
		for station in range(ceili(length)):
			for lateral:float in [-width+.8,0,width-.8]:
				var point:=start+axis*((station+.5)/length)+side*lateral
				cells[Vector2i(floori(point.x),floori(point.y))]={}
	for cell:Vector2i in cells:
		var chosen:Dictionary={};var distance:=INF
		var center:=Vector2(cell)+Vector2.ONE*.5
		for road:Dictionary in roads:
			var start:=Vector2(road.start.x,road.start.z);var finish:=Vector2(road.finish.x,road.finish.z)
			var axis:=finish-start;var length:=axis.length()
			if length<2:continue
			var fraction:float=(center-start).dot(axis)/axis.length_squared()
			var across:=absf((center-start).cross(axis))/length
			if fraction<0 or fraction>1 or across>float(road.half_width)-.75 or across>=distance:continue
			distance=across;chosen=road
		if chosen.is_empty():cells[cell]={"covered":false};continue
		var minimum:=INF;var maximum:=-INF
		for across:float in [.08,.5,.92]:
			for along:float in [.08,.5,.92]:
				var height:=profile_height(chosen,Vector2(cell)+Vector2(across,along))
				minimum=minf(minimum,height);maximum=maxf(maximum,height)
		var fit:=contact(minimum,maximum);fit["covered"]=true;fit["category"]=chosen.category;fit["cell"]=cell
		cells[cell]=fit;categories[chosen.category].sampled_cells+=1
		if not fit.fits_any_integer_cell:categories[chosen.category].unfit_cells+=1;worst.append(fit)
	worst.sort_custom(func(first:Dictionary,second:Dictionary):return maxf(first.best.gap,first.best.burial)>maxf(second.best.gap,second.best.burial))
	return {"categories":categories,"cells":cells,"worst":worst.slice(0,20),"segments":segments}
func run()->void:
	var arguments:=PackedStringArray(OS.get_cmdline_user_args())
	if not "--snapshot-readonly" in arguments or not "--temporary" in arguments:quit(2);return
	check(contact(47.02,47.08).fits_any_integer_cell,"shallowly embedded integer cell satisfies both limits")
	check(contact(46.94,46.98).fits_any_integer_cell,"small gap can satisfy both limits without deep burial")
	check(not contact(47.38,47.42).fits_any_integer_cell,"fractional road grade cannot be disguised as a fitting integer cell")
	DirAccess.make_dir_recursive_absolute(evidence)
	var view:=SubViewport.new();view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";view.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn),"read-only saved problem location loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.session_menu.set_open(false)
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(3);game.structure_shape=1;game.structure_material=0;game.structure_rotation=0;game.structure_prefab_index=-1
	for frame in 30:await process_frame
	var actual:Dictionary=game._structure_target(false)
	check(actual.has("support"),"ordinary targeting returns actual collision contact")
	var saved_pose:={"position":game.player.position,"yaw":game.yaw,"pitch":game.pitch}
	var options:Dictionary=game.world_recipe.store.decode(game.world_recipe.store.capture_snapshot())
	var normalized:=Plan.build(game.terrain.backend.world_seed,game.terrain.backend.world_generator,options,evidence.path_join("plans"))
	var off:=options.duplicate();off.road_grid=0
	var original:=Plan.build(game.terrain.backend.world_seed,game.terrain.backend.world_generator,off,evidence.path_join("plans"))
	if not check(normalized.get("ok",false) and original.get("ok",false),"both production road plans available"):await finish();return
	var before:=coverage(roads_for(original));var after:=coverage(roads_for(normalized),before.cells)
	var nearest:Array=[];var location:Vector3=actual.get("position",game.player.position)
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(preload("res://addons/volumetric_terrain/mesh_codec.gd").command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
	var reservations:=preload("res://addons/world_runtime/road_normalization.gd").protected_areas(normalized.sites)
	for road:Dictionary in roads_for(normalized):
		var start:=Vector2(road.start.x,road.start.z);var finish:=Vector2(road.finish.x,road.finish.z)
		var axis:=finish-start;var fraction:=clampf((Vector2(location.x,location.z)-start).dot(axis)/axis.length_squared(),0,1)
		var distance:float=(Vector2(location.x,location.z)-start-axis*fraction).length()
		if distance<float(road.half_width):
			var probe:Dictionary=core.normalize_roads([road],reservations)
			probe.erase("segments")
			nearest.append({"road":road,"distance":distance,"planned_height":profile_height(road,Vector2(location.x,location.z)),"normalizer_probe":probe})
	before.erase("cells");after.erase("cells")
	var result:={"failures":failures,"slot":game.terrain.save_slot,"pose":saved_pose,"actual":actual,"nearby_roads":nearest,"before":before,"after":after,"normalization":normalized.road_normalization,"quality_accepted":false,"scope":"Whole-network analytic profile screening at identical grid cells; actual collision contact only at the saved screenshot target. Corners, junctions, shoulders and stamp interactions require rendered collision coverage. Not an all-world pass.","limits":{"gap":GapLimit,"burial":BurialLimit}}
	FileAccess.open(evidence.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("GRID_NETWORK_ACTUAL ",actual)
	print("GRID_NETWORK_COVERAGE before=",before.categories," after=",after.categories)
	game.set_process(false)
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(evidence.path_join("saved_problem.png"))==OK,"captured saved problem location")
	await finish()
func _process(_delta:float)->bool:
	if is_instance_valid(game):game.app_focused=true
	return false
func finish()->void:
	if is_instance_valid(game):game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"read-only audit closes without writing save");game.queue_free();await process_frame
	print("GRID_NETWORK_AUDIT failures=",failures," quality=REJECTED");quit(1 if failures else 0)
