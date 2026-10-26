# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var group:=Vector3.ZERO
var point:=Vector3.ZERO
var monitored:Dictionary={}
var watching:=false
var missing_frames:=0
var observed_frames:=0
var folder:="res://reports/vegetation_edit_world"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func until(predicate:Callable,seconds:float)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:await process_frame
	return predicate.call()
func settled()->bool:
	var cover=game.ground_cover
	return cover.resident.size()==cover._wanted.size() and cover._dirty.is_empty() and cover._requests.is_empty() and cover._scatter_job.is_empty() and cover._support_job.is_empty()
func rows()->Dictionary:
	var out:Dictionary={}
	for child in game.ground_cover.batches[2].get_children():
		if child is MultiMeshInstance3D and child.visible and child.position==group:
			for i in child.multimesh.instance_count:
				var pose:Transform3D=child.multimesh.get_instance_transform(i);pose.origin+=child.position
				if pose.origin.distance_to(point)>6:out[str(pose)]=child.multimesh.get_instance_custom_data(i)
	return out
func observe()->void:
	if not watching:return
	observed_frames+=1;var visible:=rows()
	for key in monitored:
		if visible.get(key)!=monitored[key]:missing_frames+=1;break
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vegetation-evidence-dir="):folder=arg.trim_prefix("--vegetation-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	check(await until(func():return not game.loading_active,55),"actual world ready")
	if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.zombies.clear();game.zombies.population_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game.ground_enabled and await until(settled,45),"production ground owners finish publication")
	var cover=game.ground_cover;var nearest:=INF
	for key in cover.resident:
		var row:Dictionary=cover.resident[key][2]
		for i in row.ids.size():
			var values:PackedFloat32Array=row.transforms
			var at:=Vector3(values[i*12+3],values[i*12+7],values[i*12+11])
			if at.distance_to(game.player.global_position)<nearest:nearest=at.distance_to(game.player.global_position);point=at
	check(nearest<48,"nearby natural grass supplies the real terrain witness")
	if nearest>=48:await finish();return
	group=Vector3(floorf(point.x/32)*32,floorf(point.y/32)*32,floorf(point.z/32)*32)
	# Three controlled authored clumps force the normal bulk-exclusion route.
	# They share the natural clump's support height and remain temporary test data.
	var planted:=PackedInt64Array()
	for i in 3:planted.append(cover.removed.add(2,Transform3D(Basis.IDENTITY,point)))
	cover._exclusion_changed(AABB(point-Vector3.ONE,Vector3.ONE*2))
	check(await until(settled,25),"controlled authored clumps publish through actual density support")
	var all_present:=true
	for id in planted:all_present=all_present and cover.batches[2].get_ids().has(id)
	check(all_present,"three authored witnesses are rendered before exclusion")
	game.camera.global_position=point+Vector3(2,2.3,3);game.camera.look_at(point+Vector3.UP*.2)
	for material in cover.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
	for i in 50:await process_frame
	check(await until(settled,25),"camera owner selection settles before continuity observation")
	monitored=rows();check(monitored.size()>20,"same spatial group has unaffected visible grass to protect")
	await capture("before")
	RenderingServer.frame_post_draw.connect(observe)
	watching=true
	var cell:=Vector3i(point.floor());var word:int=game.structures.blocks.get_cell(cell)
	var inventory=game.player_hud.inventory;var before:PackedByteArray=cover.removed.capture_storage_snapshot()
	check(word==0 and game.construction_inventory.place_block(game.structures.blocks,inventory,cell,1),"paid gameplay brick placement enters real block/exclusion publication")
	check(await until(settled,25),"brick exclusion finishes")
	var hidden:=true
	for id in planted:hidden=hidden and not cover.batches[2].get_ids().has(id)
	check(hidden,"brick excludes all three overlapping clumps")
	for i in 5:await process_frame
	check(missing_frames==0,"placing a brick never hides or refades unrelated visible grass")
	await capture("brick")
	check(game.construction_inventory.place_block(game.structures.blocks,inventory,cell,word),"brick removal uses the same production coordinator")
	check(await until(settled,25),"removed brick restores original clumps")
	for i in 5:await process_frame
	check(missing_frames==0,"restoration never hides neighbouring pages")
	await capture("restored")
	var revision:int=game.terrain.density_revision
	check(game.terrain.sculpt_sphere(point,1.5,false),"real native mining edit accepted under the witnesses")
	check(await until(func():return not game.terrain.pending_edit,25) and game.terrain.density_revision>revision,"mining publishes changed native terrain")
	check(await until(settled,25),"mining support and exclusion resampling completes")
	for i in 5:await process_frame
	check(missing_frames==0 and observed_frames>10,"every observed rendered edit frame retains unaffected grass and its original fade age")
	check(cover.removed.capture_storage_snapshot()==before,"visual exclusion and mining preserve authored durable records")
	check(cover.rejected_batches==0,"no rejected ground-cover publications")
	watching=false;await capture("mined")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"unaffected_grass":monitored.size(),"observed_frames":observed_frames,"missing_frames":missing_frames,"point":point,"group":group,"scope":"Actual temporary world, paid brick coordinator, native mining and per-render-frame GPU packet continuity. Screenshot/readback overhead is not performance evidence."},"  "))
	await finish()
func finish()->void:
	watching=false
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("VEGETATION_EDIT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
