# SPDX-License-Identifier: 0BSD
extends SceneTree
const SAVE:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var game:Node3D
var boulders:Node
var failures:=0
var output:="res://reports/boulder_horizon_world"
var options:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--gameplay-construction","--ground-cover","--vehicle-fleet","--no-zombies"])
var records:Array=[]
var persistent:=false
var eye_home:Transform3D
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func until(predicate:Callable,seconds:int=90)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		game.app_focused=true;await process_frame
	return predicate.call()
func identities()->Dictionary:
	var result:Dictionary={}
	for key:Vector2i in boulders.resident:
		var row:Dictionary=boulders.resident[key][0]
		for index in row.ids.size():
			var values:PackedFloat32Array=row.transforms.slice(index*12,(index+1)*12)
			result[row.ids[index]]=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))
	return result
func settled()->bool:
	return not game.terrain.pending_edit and boulders.coverage_status().ready
func stone_count()->int:
	var total:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==201:total+=row.count
	return total
func aim(pose:Transform3D)->void:
	var point:Vector3=pose*Vector3(0,.05,.26)
	game.camera.global_position=point+pose.basis.z.normalized()*2;game.camera.look_at(point)
func strike(identity:int,pose:Transform3D)->bool:
	aim(pose)
	var target:Dictionary=game.world_attack.target()
	return target.get("kind")=="cover" and target.get("id")==identity and target.get("cover_owner")==boulders and game.world_attack.apply_target(target)
func picture(name:String,point:Vector3,offset:Vector3)->void:
	game.camera.global_position=point+offset;game.camera.look_at(point)
	if name in ["halves","quarters"]:
		var deadline:=Time.get_ticks_msec()+800
		while Time.get_ticks_msec()<deadline:game.app_focused=true;await process_frame
	for frame in 8:game.app_focused=true;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
	records.append({"view":name,"camera":game.camera.global_position,"coverage":boulders.coverage_status(),"collision":game.ground_cover.rock_collision.collision_stats()})
func close_world()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();game=null;boulders=null
	await process_frame;await process_frame

func open_world()->bool:
	load("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=not persistent;game.background_fps=60;game.player_view.settings_path=""
	root.add_child(game)
	if not await until(func():return not game.loading_active):return false
	boulders=game.ground_cover.boulders
	eye_home=game.camera.transform
	game.set_physics_process(false);game._clear_motion();game.player_view.set_process(false)
	game.player_hud.equip_item(1);game._sync_player_tool()
	return true

func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):options.append(argument)
		if argument.begins_with("--boulder-save-slot="):
			var slot:=argument.trim_prefix("--boulder-save-slot=")
			if not slot.begins_with("boulder_check_") or not slot.is_valid_identifier():quit(2);return
			options.remove_at(0);options.append("--world-slot="+slot)
			options.remove_at(options.find("--temporary"));options.remove_at(options.find("--snapshot-readonly"));persistent=true
	DirAccess.make_dir_recursive_absolute(output)
	var original_hash:=FileAccess.get_sha256(SAVE)
	if original_hash.is_empty():push_error("Missing populated fixture");quit(1);return
	var began:=Time.get_ticks_usec()
	check(await open_world(),"production world ready with whole-world boulders")
	if failures:await close_world();quit(1);return
	var load_ms:float=(Time.get_ticks_usec()-began)/1000.0
	var baseline:=identities()
	check(boulders.coverage_status().ready and baseline.size()>100,"all world owners ready before play, including never-visited boulders")
	check(game.ground_cover.fractures.statistics().roots==baseline.size(),"every accepted boulder has a native render record")
	var unique:=true
	for key:Vector2i in game.ground_cover.resident:
		unique=unique and game.ground_cover.native.boulder_rows(game.ground_cover.resident[key][0]).ids.is_empty()
	check(unique,"local grass never duplicates world boulder ownership")
	var identity:=0;var closest:=INF
	for candidate:int in baseline:
		var distance:float=baseline[candidate].origin.distance_squared_to(game.player.position)
		if distance<closest:closest=distance;identity=candidate
	if identity==0:await close_world();quit(1);return
	var pose:Transform3D=baseline[identity]
	game.player.position=pose.origin+Vector3(0,3,8)
	check(await until(func():return game.ground_cover._requests.is_empty() and game.ground_cover.resident.size()==game.ground_cover._wanted.size()),"local physics and grass settle near selected boulder")
	await picture("near",pose.origin,Vector3(10,6,12))
	await picture("transition",pose.origin,Vector3(0,40,72))
	await picture("far",pose.origin,Vector3(0,150,300))
	game.camera.transform=eye_home
	game.player_view.set_overview(true);game.player_view.overview_distance=1800
	for frame in 180:game.app_focused=true;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("overview.png"))
	check(game.ground_cover.boulder_camera==game.player_view.third_camera and game.ground_cover.fractures.statistics().near==0 and game.ground_cover.fractures.statistics().far==baseline.size(),"production overview camera selects far boulder tiers independently of player physics")
	records.append({"view":"overview","camera":game.player_view.third_camera.global_position,"coverage":boulders.coverage_status(),"collision":game.ground_cover.rock_collision.collision_stats()})
	game.player_view.set_overview(false);game.player_view.set_process(false)
	check(baseline==identities() and game.ground_cover.fractures.statistics().roots==baseline.size(),"overview retains every exact identity and pose")
	check(game.ground_cover.rock_collision.collision_stats().resident_bodies<=256,"global render keeps bounded player-local physics")
	for point:Vector3 in [Vector3(1800,100,1800),Vector3(128,100,128),pose.origin+Vector3(0,3,8)]:
		game.player.position=point;game.camera.global_position=point+Vector3.UP*3
		for frame in 180:game.app_focused=true;await process_frame
		check(await until(settled) and baseline==identities(),"physical travel and grass retirement preserve all world boulders")
	aim(pose)
	var key:=Vector2i(floori(pose.origin.x/64),floori(pose.origin.z/64))
	boulders._reconcile[key]=true
	var reused:int=boulders.unchanged_publications
	check(game.world_attack.target().get("id")==identity,"contact resolves bounded exclusion work instead of waiting behind distant owners")
	check(boulders.unchanged_publications>reused,"unchanged exclusions reuse accepted rows without rebuilding shelters or packing")
	boulders._resample[key]=true
	check(game.world_attack.target().is_empty(),"unavailable boulder cannot fall through to terrain mining")
	check(await until(settled),"pending owner reconciles before mining")
	var initial_stone:=stone_count()
	check(strike(identity,pose) and strike(identity,pose) and strike(identity,pose),"production contact targeting and harvesting damage the global boulder")
	check(game.world_attack.durability.damage("cover:%d"%identity,240)==90 and game.ground_cover.fractures.stage(identity)==1 and stone_count()==initial_stone+3,"three hits pay per-hit stone and fracture into halves")
	await picture("halves",pose.origin,Vector3(10,6,12))
	if persistent:
		var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
		var saved:Array=[]
		game.terrain.save_completed.connect(func(ok:bool):saved.append(ok))
		game.terrain.save_world()
		check(await until(func():return not saved.is_empty(),30) and saved[0],"compound world save publishes partial boulder damage")
		await close_world()
		check(await open_world(),"fresh world instance reopens the compound checkpoint")
		if failures:await close_world();quit(1);return
		check(identities()==baseline and game.world_attack.durability.damage("cover:%d"%identity,240)==90 and game.ground_cover.fractures.stage(identity)==1,"compound reload preserves every root and partial fracture")
		check(game.player_hud.inventory.capture_storage_snapshot()==inventory,"compound reload preserves mining rewards and tool wear")
	var damage:PackedByteArray=game.world_attack.durability.capture_storage_snapshot()
	check(game.world_attack.durability.restore_storage_snapshot(damage),"native damage snapshot restores")
	boulders.reset()
	check(await until(settled) and identities()==baseline and game.ground_cover.fractures.stage(identity)==1,"world renderer rebuild restores exact roots and saved fracture stage")
	check(strike(identity,pose) and strike(identity,pose) and strike(identity,pose),"continued mining damages restored halves")
	check(game.ground_cover.fractures.stage(identity)==2,"second threshold uses quarters")
	await picture("quarters",pose.origin,Vector3(10,6,12))
	check(strike(identity,pose) and strike(identity,pose),"final two production contacts complete harvest")
	check(stone_count()==initial_stone+33 and not identities().has(identity) and game.ground_cover.fractures.stage(identity)==3,"final blow grants larger reward and removes canonical interaction root")
	await picture("final_debris",pose.origin,Vector3(10,6,12))
	var second:=0;closest=INF
	var remaining:=identities()
	for candidate:int in remaining:
		var distance:float=remaining[candidate].origin.distance_squared_to(pose.origin)
		if distance<closest:closest=distance;second=candidate
	var second_pose:Transform3D=remaining[second]
	var root_point:Vector3=second_pose.origin+Vector3.UP*(.03-second_pose.basis.y.length()*.12)
	game.player.position=root_point+Vector3(0,3,8);game.camera.global_position=root_point+Vector3(0,4,9)
	check(game.terrain.edit(Codec.brush(root_point,root_point,1.5,0,false,1),Vector3.ZERO,Vector3.ZERO),"boulder root excavation admitted")
	check(await until(settled,45) and not identities().has(second),"terrain support transaction removes excavated boulder")
	var unaffected:=true
	var after:=identities()
	for candidate:int in remaining:
		if remaining[candidate].origin.distance_to(root_point)>12:unaffected=unaffected and after.get(candidate)==remaining[candidate]
	check(unaffected,"unaffected world boulders retain exact poses")
	var harvest:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	check(game.ground_cover.removed.restore_storage_snapshot(harvest),"harvest and excavation exclusions survive binary roundtrip")
	boulders.reset()
	check(await until(settled) and not identities().has(identity) and not identities().has(second),"whole-world rebuild cannot resurrect harvested or excavated boulders")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test never captures mouse")
	await close_world()
	check(FileAccess.get_sha256(SAVE)==original_hash,"source save remains byte-identical")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"load_ms":load_ms,"roots":baseline.size(),"views":records,"compound_reopen":persistent,"scope":"Production contact targeting/harvesting and binary component roundtrip; optional owned compound-save reopen. Not attack-animation input or cross-process qualification."},"  "))
	print("BOULDER_HORIZON_WORLD failures=",failures)
	quit(1 if failures else 0)
