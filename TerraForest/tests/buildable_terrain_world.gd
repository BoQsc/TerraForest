extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var chosen:=Vector3i.ZERO
var camera_height:=0.0
func _process(_delta:float)->bool:
	if is_instance_valid(game):game.app_focused=true
	return false
func survey(core:RefCounted,cell:Vector3i)->PackedFloat32Array:
	var points:=PackedVector3Array()
	for across:float in [.08,.5,.92]:
		for along:float in [.08,.5,.92]:points.append(Vector3(cell.x+across,0,cell.z+along))
	var request:=Codec.command(37,[9]);request.append_array(points.to_byte_array())
	var reply:PackedByteArray=core.execute(request);var values:=PackedFloat32Array()
	for index in 9:values.append(reply.decode_float(12+index*8))
	return values
func choose_site()->bool:
	var original:RefCounted=ClassDB.instantiate("TerrainCore");original.execute(Codec.command(6,[1703,17]))
	var revised:RefCounted=ClassDB.instantiate("TerrainCore");revised.execute(Codec.command(6,[1703,20]))
	var origin:=Vector3i(game.player.position.floor());var nearest:=INF
	for across in range(-36,37,2):
		for along in range(-36,37,2):
			var cell:=origin+Vector3i(across,0,along);var before:=survey(original,cell);var after:=survey(revised,cell)
			var old_high:float=Array(before).max();var new_high:float=Array(after).max();var new_low:float=Array(after).min()
			var bottom:=ceilf(new_high-.2-.00001)
			if bottom-new_high<=.03 and bottom-new_low<=.1 and bottom-old_high>.20 and float(across*across+along*along)<nearest:
				chosen=Vector3i(cell.x,int(bottom),cell.z);camera_height=maxf(old_high,new_high)+1.7;nearest=float(across*across+along*along)
	return is_finite(nearest)
func capture(label:String)->void:
	game.structures.blocks.flush_bakes();game.shape_preview.hide();game.prefab_preview.hide();game.set_process(false)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(label+".png"));game.set_process(true)
func run()->void:
	evidence="res://reports/buildable_terrain_world";DirAccess.make_dir_recursive_absolute(evidence)
	var original_arguments:=PackedStringArray(OS.get_cmdline_user_args())
	var results:Array=[]
	for profile:int in [19,21]:
		var arguments:=original_arguments.duplicate()
		arguments.append_array(PackedStringArray(["--world-generator="+str(profile),"--world-seed=1703","--gameplay-construction","--ground-cover","--no-zombies","--nearby-first"]))
		ProjectSettings.set_setting("terraforest/session_arguments",arguments)
		game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
		if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"playable comparison world loads profile %d"%profile):
			print("LOAD_STATE ",JSON.stringify({"loading":game.loading_active,"floor":game.needs_floor_spawn,"ready":game.terrain.world_ready,"error":game.terrain.latest_error,"player":game.player.position,"stage":game.loading_stage_text,"work":game.loading_work_text}));await finish();return
		game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.session_menu.set_open(false)
		if chosen==Vector3i.ZERO and not check(choose_site(),"nearby natural site improves grid contact without editing terrain"):await finish();return
		aim(Vector3(chosen)+Vector3(.5,.1,3.0),Vector3(chosen)+Vector3(.5,0,.5))
		game.camera.global_position=Vector3(chosen.x+.5,camera_height,chosen.z+3.0);game.camera.look_at(Vector3(chosen)+Vector3(.5,0,.5))
		game.terrain.focus=game.player.position;game.structures.set_model_focus(game.player.position)
		if not check(await wait_for(func():return game._placement_collision_ready(AABB(Vector3(chosen)-Vector3.ONE,Vector3.ONE*3)),30),"comparison location collision is ready"):await finish();return
		game.player_hud.equip_item(101)
		var target:Dictionary=game._structure_target(false)
		if not check(target.get("placement_ok",false),"existing placement rules accept profile %d"%profile):print("TARGET ",target);await finish();return
		var before:=amount(101);game._edit_structure(false)
		check(game.structures.blocks.get_cell(target.target)==1 and amount(101)==before-1,"ordinary paid click places the aimed block")
		var support:Dictionary=target.support
		results.append({"profile":profile,"target":target.target,"support":support})
		print("ACTUAL_GROUND_CONTACT ",JSON.stringify(results[-1]))
		if profile==21:check(support.bottom-support.maximum<.04 and support.gap<.12,"rendered terrain collision closes the old gap")
		await capture("profile_%d_ground"%profile)
		game.camera.global_position=Vector3(chosen)+Vector3(0,8,15);game.camera.look_at(Vector3(chosen))
		await capture("profile_%d_landscape"%profile)
		if profile==21:
			game.construction_inventory.gameplay=false
			var floating:=chosen+Vector3i(3,5,0)
			game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,1]));game.structures.blocks.flush_bakes()
			game.camera.global_position=Vector3(floating)+Vector3(.5,.5,3);game.camera.look_at(Vector3(floating)+Vector3.ONE*.5)
			await wait_for(func():return game._placement_collision_ready(AABB(Vector3(floating),Vector3.ONE*2)),10)
			var aerial:Dictionary=game._structure_target(false)
			check(aerial.get("placement_ok",false),"floating block-face attachment remains allowed")
			game._edit_structure(false)
			check(aerial.has("target") and game.structures.blocks.get_cell(aerial.target)==1,"actual input handler extends floating construction")
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	ProjectSettings.set_setting("terraforest/session_arguments",null)
	FileAccess.open(evidence.path_join("contact.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("BUILDABLE_TERRAIN_WORLD failures=",failures);quit(1 if failures else 0)
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	ProjectSettings.set_setting("terraforest/session_arguments",null)
	print("BUILDABLE_TERRAIN_WORLD failures=",failures);quit(1)
