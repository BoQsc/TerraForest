extends "res://tests/combined_resource_route.gd"

var view:=SubViewport.new()
var captures:Array=[]

func picture(label:String)->void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	check(image.save_png(evidence.path_join(label+".png"))==OK,"capture "+label)
	captures.append(label)

func run()->void:
	var arguments:=OS.get_cmdline_user_args()
	var slot:=""
	var camera_values:=PackedStringArray()
	for argument in arguments:
		if argument.begins_with("--darkness-evidence="):evidence=argument.trim_prefix("--darkness-evidence=")
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
		if argument.begins_with("--darkness-camera="):camera_values=argument.trim_prefix("--darkness-camera=").split(",")
	if evidence.is_empty() or not slot.begins_with("mining_darkness_") or "--snapshot-readonly" not in arguments or "--temporary" not in arguments:quit(2);return
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";view.add_child(game)
	game.set_physics_process(false)
	if not check(await wait_for(func():return not game.loading_active and not game.waiting_spawn and game.terrain.snapshot_restore_ok,90),"saved excavation loads read-only"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.session_menu.set_open(false)
	game.player_view.set_enabled(false,false)
	for frame in 120:await process_frame
	game.set_process(false)
	game.shape_preview.hide();game.prefab_preview.hide()
	if not camera_values.is_empty():
		if not check(camera_values.size()==12,"diagnostic camera has twelve components"):await finish();return
		var components:=PackedFloat32Array()
		for value in camera_values:
			if not check(value.is_valid_float() and is_finite(float(value)),"diagnostic camera component is finite"):await finish();return
			components.append(float(value))
		game.camera.global_transform=Transform3D(Basis(Vector3(components[0],components[1],components[2]),Vector3(components[3],components[4],components[5]),Vector3(components[6],components[7],components[8])),Vector3(components[9],components[10],components[11]))
	var metadata:={"position":str(game.player.position),"camera":str(game.camera.global_transform),"lamp_position":str(game.flashlight.global_position),"lamp_default_visible":game.flashlight.visible,"sun_shadow_bias":game.sun.shadow_bias,"torch_bias":game.flashlight.shadow_bias,"torch_normal_bias":game.flashlight.shadow_normal_bias,"captures":captures}
	await picture("01_saved_pose")
	game.flashlight.visible=false
	await picture("00_no_lamp")
	var original_shader:Shader=game.terrain_material.shader
	var original_cached_sun:Variant=game.terrain_material.get_shader_parameter("cached_sun_enabled")
	game.terrain_material.set_shader_parameter("cached_sun_enabled",false)
	await picture("06_engine_sun_only")
	game.terrain_material.set_shader_parameter("cached_sun_enabled",original_cached_sun)
	var sky_expression:="sqrt(clamp(visibility.x,0.0,1.0))"
	if check(original_shader.code.contains(sky_expression),"diagnostic finds cached sky expression"):
		var comparison:=Shader.new()
		comparison.code=original_shader.code.replace(sky_expression,"1.0")
		game.terrain_material.shader=comparison
		await picture("07_unoccluded_sky")
	game.terrain_material.shader=original_shader
	var original_minimum_fill:Variant=game.terrain_material.get_shader_parameter("minimum_cave_fill")
	game.terrain_material.set_shader_parameter("minimum_cave_fill",0.0)
	await picture("08_strict_cavity")
	game.terrain_material.set_shader_parameter("minimum_cave_fill",original_minimum_fill)
	game.flashlight.visible=true
	await picture("02_torch")
	game.flashlight.shadow_enabled=false
	await picture("03_torch_no_shadows")
	game.flashlight.shadow_enabled=true
	for mode in [3,4,5,6]:
		game.terrain_material.set_shader_parameter("debug_view",mode)
		await picture("debug_%d"%mode)
	game.terrain_material.set_shader_parameter("debug_view",0)
	game.flashlight.position=Vector3.ZERO
	await picture("04_torch_at_eye")
	game.flashlight.shadow_normal_bias=.2
	await picture("05_torch_small_bias")
	FileAccess.open(evidence.path_join("scene.json"),FileAccess.WRITE).store_string(JSON.stringify(metadata,"  "))
	await finish()

func finish()->void:
	if is_instance_valid(game):
		var core:RefCounted=game.terrain.backend.native
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
		var snapshot:PackedByteArray=core.execute(preload("res://addons/volumetric_terrain/mesh_codec.gd").command(4,[3]))
		FileAccess.open(evidence.path_join("terrain.bin"),FileAccess.WRITE).store_buffer(snapshot.slice(12))
		game.free();await process_frame;await process_frame
	print("MINING_DARKNESS failures=",failures);quit(1 if failures else 0)
