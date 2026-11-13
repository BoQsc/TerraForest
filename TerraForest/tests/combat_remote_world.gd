# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node3D
var failures:=0
var slot:="recipe_generated_4644d8cfc8f97e43"
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var save:="user://worlds/"+slot+".trw"
	if not FileAccess.file_exists(save):check(false,"existing default-world fixture exists");quit(1);return
	var hash:=FileAccess.get_sha256(save)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--gameplay-construction","--ground-cover","--actors","--temporary","--no-derived-cache"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+150000
	var next_progress:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		if Time.get_ticks_msec()>=next_progress:
			var request:Dictionary=game.lakes.water.next_request()
			var solids:Dictionary=game.structures.blocks.solid_hulls(AABB(Vector3(request.get("coordinate",Vector3i.ZERO))*4,Vector3.ONE*4))
			print("REMOTE_LOAD ",game.loading_stage_text," | ",game.loading_work_text," detail=",JSON.stringify({"request":request,"hulls_ok":solids.ok,"hulls_unavailable":solids.unavailable,"terrain_pending":game.terrain.pending_edit,"lake_pending":game.terrain.backend._lake_pending,"builder":game.lakes._builder!=null,"cached_task":game.lakes._cached_task,"water":game.lakes.statistics()}))
			next_progress+=30000
		await process_frame
	check(not game.loading_active and game.terrain.backend.readonly_snapshot,"existing default world loads read-only")
	if failures:await finish();return
	game.set_process(false);game.set_physics_process(false);game.combat.set_physics_process(false)
	check(game.combat.blast_water_settling,"terrain-reactive water is enabled in normal gameplay")
	if OS.get_cmdline_user_args().has("--verify-water-settling"):game.combat.blast_water_settling=true
	game.player_view.entry.finish();game._clear_motion();game.player.set_physics_process(false)
	game.zombies.population_enabled=false
	var player_before:Vector3=game.player.global_position
	var base:Vector3=player_before+Vector3(160,3,0)
	if base.x>1980:base.x-=320
	var ids:Array[int]=[]
	for n in 3:
		var p:=base+Vector3(3*n,0,0)
		ids.append(game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,p.x,0,1,0,p.y,0,0,1,p.z]),AABB()))
	check(not game._actor_collision_ready(AABB(base-Vector3.ONE*6,Vector3.ONE*12)),"remote blast lies outside player collision readiness")
	check(game.combat.damage_barrel(ids[0],50),"remote chain ignites")
	var before:int=game.combat.explosions
	deadline=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		game.combat.step_blasts()
		if not game.terrain.pending_edit and not game.combat.detonations.is_empty():
			if game.combat.detonate(game.combat.detonations[0]):game.combat.detonations.pop_front()
		if game.combat.explosions-before==3 and not game.terrain.pending_edit and game.combat.blast_jobs.is_empty():break
		await process_frame
	check(game.combat.explosions-before==3,"three actual-world barrels detonate without following them")
	check(not game.terrain.pending_edit and game.combat.blast_jobs.is_empty(),"terrain and building publication finish")
	check(game.player.global_position==player_before,"player stays at original location")
	if OS.get_cmdline_user_args().has("--verify-water-settling"):
		var lake:Dictionary={};var distance:=INF
		for candidate:Dictionary in game.lakes._lakes.values():
			var d:float=candidate.seed.distance_squared_to(player_before)
			if d<distance:distance=d;lake=candidate
		check(not lake.is_empty(),"existing saved world contains an authored lake")
		if not lake.is_empty():
			var center:Vector3=lake.seed;center.y=lake.level-2
			var owned:int=game.lakes.statistics().water_ml
			var lake_barrel:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,center.x,0,1,0,center.y,0,0,1,center.z]),AABB())
			check(game.combat.damage_barrel(lake_barrel,50) and game.combat.detonate(lake_barrel),"barrel excavates the existing saved world's lake")
			game.combat.detonations.erase(lake_barrel)
			deadline=Time.get_ticks_msec()+45000
			var settled:=false
			while Time.get_ticks_msec()<deadline:
				game.app_focused=true
				var water:Dictionary=game.lakes.statistics()
				if not water.equilibrium_failure.is_empty():break
				if not game.terrain.pending_edit and water.render_ready and water.settling_regions==0:settled=true;break
				await process_frame
			var water:Dictionary=game.lakes.statistics()
			print("EXISTING_LAKE_WATER ",JSON.stringify({"settled":settled,"cells":water.equilibrium_cells,"failure":water.equilibrium_failure,"owned_before":owned,"owned_after":water.water_ml,"surface_failure":water.surface_failure}))
			check(settled and water.equilibrium_cells>0 and water.water_ml==owned,"existing multi-lake world settles the barrel edit without losing finite water")
			if settled and OS.get_cmdline_user_args().has("--water-capture-existing"):
				var evidence:=""
				for argument:String in OS.get_cmdline_user_args():
					if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
				check(not evidence.is_empty(),"existing-world capture has an admitted evidence directory")
				if not evidence.is_empty():
					game.tool_view.visible=false;game.combat.effects.step(.6,true)
					for underwater in [false,true]:
						game.camera.global_position=center+(Vector3(2,.5,2) if underwater else Vector3(8,5,8))
						game.camera.look_at(center+Vector3(0,0 if underwater else 1,0),Vector3.UP)
						game.water_camera.update()
						for frame in 4:await process_frame
						await RenderingServer.frame_post_draw
						var label:="existing_lake_underwater" if underwater else "existing_lake_after"
						check(root.get_texture().get_image().save_png(evidence.path_join(label+".png"))==OK,"saved-world water capture writes "+label)

	check(FileAccess.get_sha256(save)==hash and game.terrain.backend.readonly_snapshot,"source fixture remains unchanged")
	await finish()
func finish()->void:
	if is_instance_valid(game):game.terrain.shutdown();game.free()
	await process_frame;await process_frame
	print("COMBAT_REMOTE_WORLD failures=",failures)
	quit(1 if failures else 0)
