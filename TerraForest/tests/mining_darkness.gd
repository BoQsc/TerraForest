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
	for argument in arguments:
		if argument.begins_with("--darkness-evidence="):evidence=argument.trim_prefix("--darkness-evidence=")
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
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
	var metadata:={"position":str(game.player.position),"camera":str(game.camera.global_transform),"lamp_position":str(game.flashlight.global_position),"lamp_default_visible":game.flashlight.visible,"sun_shadow_bias":game.sun.shadow_bias,"torch_bias":game.flashlight.shadow_bias,"torch_normal_bias":game.flashlight.shadow_normal_bias,"captures":captures}
	await picture("01_saved_pose")
	game.flashlight.visible=false
	await picture("00_no_lamp")
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
