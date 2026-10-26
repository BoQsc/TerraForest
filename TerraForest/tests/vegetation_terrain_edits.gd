extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var game:Node
var failures:=0
var checks:=0
var samples:Array=[]
var centers:Array[Vector3]=[]
var folder:="res://reports/vegetation_terrain_edits"
var visual:=false
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok
func until(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func settled()->bool:
	var cover=game.ground_cover
	return not game.loading_active and not game.terrain.pending_edit and cover.resident.size()==cover._wanted.size() and cover._retiring.is_empty() and cover._dirty.is_empty() and cover._requests.is_empty() and cover._scatter_job.is_empty() and cover._support_job.is_empty() and game.ecosystem._requests.is_empty() and game.ecosystem._resample.is_empty() and game.ecosystem._reconcile.is_empty()
func rows()->Dictionary:
	var result:Dictionary={}
	for owner:Array in game.ground_cover.resident.values():
		for species in owner.size():
			var row:Dictionary=owner[species]
			for index in row.ids.size():result[row.ids[index]]={"species":species,"values":row.transforms.slice(index*12,(index+1)*12)}
	return result
func choose()->Dictionary:
	var selected:Dictionary={};var nearest:=INF
	for key:Vector2i in game.ground_cover.resident:
		var row:Dictionary=game.ground_cover.resident[key][2]
		for index in row.ids.size():
			var values:PackedFloat32Array=row.transforms
			var point:=Vector3(values[index*12+3],values[index*12+7]+.03,values[index*12+11])
			var distance:float=point.distance_squared_to(game.player.global_position)
			if distance>nearest:continue
			var overlap:=false
			for previous:Vector3 in centers:overlap=overlap or point.distance_squared_to(previous)<36
			if overlap:continue
			nearest=distance;selected={"id":row.ids[index],"point":point,"key":key}
	return selected
func submit(packet:PackedByteArray,label:String)->bool:
	var started:=Time.get_ticks_usec()
	if not check(game.terrain.edit(packet,Vector3.ZERO,Vector3.ZERO),label+" accepted"):return false
	if not check(await until(func():return not game.terrain.pending_edit or not game.terrain.world_ready,45) and game.terrain.world_ready,label+" publishes successfully"):return false
	samples.append({"label":label,"total_ms":(Time.get_ticks_usec()-started)/1000.0,"support_worker_ms":game.terrain.last_support_worker_ms,"support_publish_ms":game.terrain.last_support_publish_ms,"instances":game.terrain.last_support_instances})
	samples[-1]["support_capture_ms"]=game.terrain.last_support_capture_ms
	var native_timings:Array=[]
	for batch:Node in game.ground_cover.batches:native_timings.append(batch.render_stats().removal_timing)
	samples[-1]["removal_native_cumulative_us"]=native_timings
	return true
func preserved(before:Dictionary,after:Dictionary,point:Vector3,radius:float)->bool:
	for identity in before:
		var values:PackedFloat32Array=before[identity].values
		if Vector3(values[3],values[7],values[11]).distance_to(point)>radius and after.get(identity)!=before[identity]:return false
	for identity in after:
		if not before.has(identity) or before[identity]!=after[identity]:return false
	return true
func capture(label:String)->void:
	if not visual:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func _initialize()->void:run.call_deferred()
func run()->void:
	visual="--vegetation-visual" in OS.get_cmdline_user_args()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--vegetation-evidence-dir="):folder=argument.trim_prefix("--vegetation-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await until(func():return not game.loading_active,60),"isolated production world loaded"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.zombies.clear();game.zombies.population_enabled=false
	if not check(game.ground_enabled and await until(settled,55),"natural trees and all ground-cover species settled"):await finish();return
	game.terrain.set_brush_active(true)
	var original_count:=rows().size()
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	for mode in 6:
		var target:=choose()
		if not check(not target.is_empty(),"nearby independent grass witness "+str(mode)):break
		var point:Vector3=target.point;centers.append(point)
		var before:=rows()
		var packet:PackedByteArray
		if mode<4:packet=Codec.brush(point+Vector3.UP*(.35 if mode%2 else -.3),point+Vector3.UP*(.35 if mode%2 else -.3),.8,mode/2,mode%2==1,1)
		elif mode==4:packet=Codec.command(3,[floori(point.x),floori(point.y+.08),floori(point.z),1])
		else:packet=Codec.command(38,[roundi(point.x),ceili(point.y+.1),roundi(point.z),1])
		if not await submit(packet,"terrain tool "+str(mode)):break
		var after:=rows()
		check(not after.has(target.id) and game.ground_cover.removed.contains(target.id),"affected clump removed durably before edit completion "+str(mode))
		check(not game.ground_cover.batches[2].get_ids().has(target.id),"rendered identity removed in same publication "+str(mode))
		check(preserved(before,after,point,3),"neighbouring clumps unchanged with no cell clearing or regrowth "+str(mode))
		check(game.terrain.last_support_instances<original_count/8,"small stroke samples local roots, not the forest "+str(mode))
	game.terrain.set_brush_active(false)
	if failures:await finish();return
	var target:=choose();var point:Vector3=target.point;centers.append(point)
	var cover=game.ground_cover
	var authored:int=cover.removed.add(2,Transform3D(Basis.IDENTITY,point+Vector3.UP*.02))
	cover._dirty[target.key]=true
	check(authored>0 and await until(settled,30) and cover.batches[2].get_ids().has(authored),"player-planted vegetation is present before excavation")
	if await submit(Codec.brush(point,point,1.2,0,false,1),"authored plant mining"):
		check(not cover.batches[2].get_ids().has(authored) and cover.removed.profile().placed==0,"mining destroys authored plant state and rendering together")
	var tree_id:=0;var tree_point:=Vector3.ZERO;var nearest:=INF
	for identity in game.vegetation.renderer.roots:
		var pose:Transform3D=game.vegetation.renderer.roots[identity].t
		var distance:float=pose.origin.distance_squared_to(game.player.global_position)
		if distance<nearest:nearest=distance;tree_id=identity;tree_point=pose.origin+Vector3.UP*.2
	check(tree_id>0,"natural tree witness available")
	var trees:Dictionary={}
	for identity in game.vegetation.renderer.roots:trees[identity]=game.vegetation.renderer.roots[identity].t
	if await submit(Codec.brush(tree_point-Vector3.UP*.4,tree_point-Vector3.UP*.4,1.4,0,false,1),"tree root mining"):
		check(not game.vegetation.renderer.roots.has(tree_id) and not game.vegetation.trunk_collision.get_ids().has(tree_id) and game.ecosystem.harvest_state.contains(tree_id),"unsupported tree, trunk collider and persistent identity update together")
		var same:=true
		for identity in trees:
			if trees[identity].origin.distance_to(tree_point)>3:same=same and game.vegetation.renderer.roots.has(identity) and game.vegetation.renderer.roots[identity].t==trees[identity]
		check(same,"tree neighbours retain exact transforms")
	var elevated_id:=0;var elevated_point:=Vector3.ZERO;nearest=INF
	for identity in game.vegetation.renderer.roots:
		var pose:Transform3D=game.vegetation.renderer.roots[identity].t
		var distance:float=pose.origin.distance_squared_to(game.player.global_position)
		if distance<nearest:nearest=distance;elevated_id=identity;elevated_point=pose.origin+Vector3.UP*4.2
	if await submit(Codec.brush(elevated_point,elevated_point,.8,0,true,1),"elevated trunk deposit"):
		check(not game.vegetation.renderer.roots.has(elevated_id) and game.ecosystem.harvest_state.contains(elevated_id),"terrain occupying a trunk removes that tree even when its root remains supported")
	target=choose();point=target.point;var before:=rows()
	game.camera.global_position=point+Vector3(10,9,12);game.camera.look_at(point)
	for frame in 5:await process_frame
	check(await until(settled,30),"camera relocation and owner retirement settle before large-edit comparison")
	await capture("before_volume");before=rows()
	if await submit(Codec.brush(point-Vector3.UP*3,point-Vector3.UP*3,12,1,false,1),"large excavation"):
		var after:=rows();check(before.size()-after.size()>50,"large volume removes individual intersected clumps in bulk")
		check(preserved(before,after,point,24),"large edit preserves exact surrounding plants")
		await capture("after_volume")
	before=rows()
	if await submit(Codec.brush(point,point,64,1,false,1),"fully populated maximum excavation"):
		var after:=rows()
		check(before.size()-after.size()>2000,"maximum brush clears thousands of resident plants, not an empty aerial fixture")
		check(preserved(before,after,point,112),"maximum brush preserves every distant identity and transform")
		check(game.terrain.last_support_publish_ms<16,"maximum populated vegetation publication stays below 16 ms on this machine")
	var snapshot:PackedByteArray=cover.removed.capture_storage_snapshot()
	var clone=ClassDB.instantiate("NativeGroundCoverState")
	check(clone.restore_storage_snapshot(snapshot) and clone.capture_storage_snapshot()==snapshot,"removal history roundtrips exactly")
	var harvested:PackedByteArray=game.ecosystem.harvest_state.capture_storage_snapshot()
	var forest=ClassDB.instantiate("NativeHarvestState")
	check(forest.restore_storage_snapshot(harvested) and forest.contains(tree_id),"tree removal survives fresh storage restoration")
	cover.reset();game.ecosystem.reset()
	check(await until(settled,60),"vegetation unload and deterministic regeneration completes")
	check(cover.removed.capture_storage_snapshot()==snapshot and not game.vegetation.renderer.roots.has(tree_id),"streaming cannot resurrect destroyed plants or trees")
	check(cover.rejected_batches==0 and game.ecosystem.rejected_batches==0,"no rejected vegetation publication")
	check(game.player_hud.inventory.capture_storage_snapshot()==inventory,"terrain clearing grants no free harvest rewards")
	await finish()
func finish()->void:
	game.terrain.set_brush_active(false)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"visual":visual},"  "))
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("VEGETATION_TERRAIN_EDITS failures=",failures);quit(1 if failures else 0)
