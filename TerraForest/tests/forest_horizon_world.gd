# SPDX-License-Identifier: 0BSD
extends SceneTree

const SAVE:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var game:Node3D
var failures:=0
var output:="res://reports/forest_horizon_world"
var options:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--gameplay-construction","--ground-cover","--vehicle-fleet"])
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func until(predicate:Callable,seconds:int=120)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		game.app_focused=true;await process_frame
	return predicate.call()
func identities()->Dictionary:
	var result:Dictionary={}
	for identity:int in game.vegetation.renderer.roots:result[identity]=game.vegetation.renderer.roots[identity].t
	return result
func settled()->bool:
	return not game.terrain.pending_edit and game.ecosystem.coverage_status().ready
func close_world()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();game=null
	await process_frame;await process_frame
	var diagnostics:RefCounted=ClassDB.instantiate("NativeStructureQueries")
	check(diagnostics.exclusion_stats().live_pages==0,"world teardown releases all native exclusion pages")
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):options.append(argument)
	DirAccess.make_dir_recursive_absolute(output)
	var original_hash:=FileAccess.get_sha256(SAVE)
	if original_hash.is_empty():push_error("Missing disposable populated fixture");quit(1);return
	var loads:=[]
	var baseline:Dictionary={}
	for pass_index in 2:
		load("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
		var began:=Time.get_ticks_usec()
		game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path=""
		root.add_child(game)
		check(await until(func():return not game.loading_active),"cold/warm production world ready "+str(pass_index))
		if failures:await close_world();break
		var load_ms:float=(Time.get_ticks_usec()-began)/1000.0
		game.set_physics_process(false);game._clear_motion()
		check(game.ecosystem.coverage_status().ready and game.ecosystem.resident.size()==1024,"all forest owners ready before play")
		check(game.vegetation.renderer.roots.size()>6000,"never-visited forest trees exist")
		var initial:=identities()
		if pass_index==0:baseline=initial
		else:check(baseline==initial,"warm reload restores every exact accepted identity and pose")
		game.player_view.set_overview(true);game.player_view.overview_distance=1800
		for frame in 120:game.app_focused=true;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("forest_%d.png"%pass_index))
		check(initial==identities(),"overview does not change canonical forest membership")
		check(game.vegetation.trunk_collision.collision_stats().resident_bodies<=256,"global forest retains 256 maximum local trunk bodies")
		loads.append({"pass":pass_index,"load_ms":load_ms,"trees":initial.size(),"coverage":game.ecosystem.coverage_status(),"trunks":game.vegetation.trunk_collision.collision_stats(),"forest":game.vegetation.statistics(),"cache":game.terrain.derived_metrics,"exclusions":game.structures.exclusion_stats()})
		if pass_index==0:
			game.player_view.set_overview(false)
			var origin:Vector3=game.player.position
			var residency_samples:=[]
			var storage:Dictionary=game.structures.blocks.capture_storage_state()
			var keys:PackedInt32Array=storage.unavailable_keys
			check(keys.size()>=3,"populated fixture has actual unloaded block regions")
			var destination:=origin
			if keys.size()>=3:destination=Vector3(keys[0]*64+32,keys[1]*64+32,keys[2]*64+32)
			var admitted_before:int=game.structures.region_paging_stats().admitted
			var evicted_before:int=game.structures.region_paging_stats().evicted
			for point:Vector3 in [destination,destination+Vector3(1200,0,1200),origin]:
				game.player.position=point
				var stable_membership:=true
				for frame in 360:
					game.app_focused=true
					await process_frame
					if frame%15==0:stable_membership=identities()==initial and stable_membership
				check(await until(settled,45) and stable_membership and identities()==initial,"physical stream-in/out retains every exact forest identity")
				residency_samples.append({"position":point,"blocks":game.structures.region_paging_stats(),"models":game.structures._model_scheduler.stats(),"exclusions":game.structures.exclusion_stats()})
			check(game.structures.region_paging_stats().admitted>admitted_before and game.structures.region_paging_stats().evicted>evicted_before,"test actually admits and retires authored building regions")
			loads[-1]["residency_samples"]=residency_samples
			var identity:=0;var closest:=INF
			for candidate:int in initial:
				var distance:float=initial[candidate].origin.distance_squared_to(game.player.position)
				if distance<closest:closest=distance;identity=candidate
			var harvested:Dictionary=game.ecosystem.harvest_root(identity,game.player_hud.inventory)
			check(harvested.get("ok",false),"actual gameplay harvesting accepts tree from whole-world catalog")
			check(await until(settled) and not game.vegetation.renderer.roots.has(identity),"harvest removes far and near tree representations")
			var recorded:PackedByteArray=game.ecosystem.harvest_state.capture_storage_snapshot()
			var clone:RefCounted=ClassDB.instantiate("NativeHarvestState")
			check(clone.restore_storage_snapshot(recorded) and clone.contains(identity),"harvest exclusion survives binary persistence roundtrip")
			var mined_id:=0;closest=INF
			for candidate:int in game.vegetation.renderer.roots:
				var pose:Transform3D=game.vegetation.renderer.roots[candidate].t
				var distance:float=pose.origin.distance_squared_to(game.player.position)
				if distance<closest:closest=distance;mined_id=candidate
			var point:Vector3=game.vegetation.renderer.roots[mined_id].t.origin
			var before:=identities()
			var edit_begin:=Time.get_ticks_usec()
			check(game.terrain.edit(Codec.brush(point,point,1.5,0,false,1),Vector3.ZERO,Vector3.ZERO),"root excavation admitted")
			check(await until(settled,45),"root excavation publishes with whole-world forest")
			loads[-1]["root_edit_ms"]=(Time.get_ticks_usec()-edit_begin)/1000.0
			loads[-1]["support_capture_ms"]=game.terrain.last_support_capture_ms
			check(not game.vegetation.renderer.roots.has(mined_id) and game.ecosystem.harvest_state.contains(mined_id),"excavation removes exact tree and persistent identity")
			var intact:=true
			for candidate:int in before:
				if before[candidate].origin.distance_to(point)>4:intact=intact and game.vegetation.renderer.roots.has(candidate) and game.vegetation.renderer.roots[candidate].t==before[candidate]
			check(intact,"unaffected whole-world roots retain exact transforms")
			game.ecosystem.reset()
			check(await until(settled,60) and not game.vegetation.renderer.roots.has(identity) and not game.vegetation.renderer.roots.has(mined_id),"rebuilding all owner pages cannot resurrect harvested or excavated trees")
		await close_world()
	check(FileAccess.get_sha256(SAVE)==original_hash,"source save remains byte-identical")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test never captures mouse")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"loads":loads},"  "))
	print("FOREST_HORIZON_WORLD failures=",failures)
	quit(1 if failures else 0)
