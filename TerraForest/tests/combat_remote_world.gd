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
	while game.loading_active and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():await process_frame
	check(not game.loading_active and game.terrain.backend.readonly_snapshot,"existing default world loads read-only")
	if failures:await finish();return
	game.set_process(false);game.set_physics_process(false);game.combat.set_physics_process(false)
	check(not game.combat.blast_water_settling,"experimental water settling stays disabled in normal gameplay")
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
	check(FileAccess.get_sha256(save)==hash and game.terrain.backend.readonly_snapshot,"source fixture remains unchanged")
	await finish()
func finish()->void:
	if is_instance_valid(game):game.terrain.shutdown();game.free()
	await process_frame;await process_frame
	print("COMBAT_REMOTE_WORLD failures=",failures)
	quit(1 if failures else 0)
