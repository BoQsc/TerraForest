extends SceneTree
var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/vegetation_steep_mining"
const HIT=Vector3(407.7924,76.17006,227.1653)
const NORMAL=Vector3(-.481736,.760515,-.435371)
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
	return not game.loading_active and not game.terrain.pending_edit and cover.resident.size()==cover._wanted.size() and cover._dirty.is_empty() and cover._requests.is_empty() and cover._scatter_job.is_empty() and cover._support_job.is_empty() and game.ecosystem._requests.is_empty() and game.ecosystem._resample.is_empty() and game.ecosystem._reconcile.is_empty()
func cover_rows()->Dictionary:
	var rows:Dictionary={}
	for owner in game.ground_cover.resident.values():
		for species:Dictionary in owner:
			for index in species.ids.size():rows[species.ids[index]]=species.transforms.slice(index*12,(index+1)*12)
	return rows
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func _initialize()->void:run.call_deferred()
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vegetation-evidence-dir="):folder=argument.trim_prefix("--vegetation-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await until(func():return not game.loading_active,55),"temporary world ready"):await finish();return
	if not check(game.terrain.backend.world_seed==1703 and game.terrain.backend.world_generator==21,"live world uses the reproduced seed and generator"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false
	game.zombies.clear();game.zombies.population_enabled=false
	game.teleport(HIT+NORMAL*4)
	if not check(await until(func():return not game.loading_active,40),"mountainside terrain ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false
	game.player.position=HIT+NORMAL*4;game.camera.global_position=HIT+NORMAL*4+Vector3.UP;game.camera.look_at(HIT)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.player_hud.equip_item(1)
	for frame in 5:await process_frame
	if not check(game.ground_enabled and await until(settled,45),"grass and tree owners finish before mining"):await finish();return
	for material in game.ground_cover.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
	var before:=cover_rows()
	var owners:Array=game.ground_cover.resident.keys()
	var trees:PackedInt64Array=game.vegetation.renderer.roots.keys()
	var saved:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	check(before.size()>100,"surrounding natural vegetation is resident, not an empty test")
	await capture("before")
	var revision:int=game.terrain.density_revision
	check(game.world_attack.destroy({"kind":"terrain","position":HIT,"normal":NORMAL}),"production pickaxe destruction submits its normal 0.65 m mining brush")
	check(await until(func():return not game.terrain.pending_edit,30) and game.terrain.density_revision>revision,"mining publishes actual terrain changes")
	check(await until(settled,45),"normal asynchronous vegetation revalidation completes")
	var after:=cover_rows();var added:=0;var changed_distant:=0
	for identity in after:
		if not before.has(identity):added+=1
	for identity in before:
		var values:PackedFloat32Array=before[identity]
		var point:=Vector3(values[3],values[7],values[11])
		if point.distance_to(HIT)>4 and after.get(identity)!=values:changed_distant+=1
	check(game.ground_cover.resident.keys()==owners,"stationary camera retains the same vegetation owners")
	check(added==0,"mining bare mountain terrain creates no new natural vegetation identities")
	check(changed_distant==0,"unaffected neighbouring vegetation retains its transforms")
	var new_trees:=0
	for identity in game.vegetation.renderer.roots:
		if not trees.has(identity):new_trees+=1
	check(new_trees==0,"mining creates no previously absent trees")
	check(saved==game.ground_cover.removed.capture_storage_snapshot(),"mining leaves authored and gathered vegetation records unchanged")
	check(game.ground_cover.rejected_batches==0,"no ground-cover publication rejection")
	for frame in 30:await process_frame
	await capture("after")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"before":before.size(),"after":after.size(),"added":added,"new_trees":new_trees,"changed_distant":changed_distant,"scope":"Temporary production world, actual pickaxe destruction coordinator and asynchronous vegetation publication; not input-animation or sustained performance qualification."},"  "))
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("VEGETATION_STEEP_MINING checks=",checks," failures=",failures);quit(1 if failures else 0)
