# SPDX-License-Identifier: 0BSD
extends SceneTree
var folder:=""
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
	run.call_deferred()
func run()->void:
	if folder.is_empty():quit(1);return
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(folder.path_join("frames"))
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("bad4dc")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("d8e3ed");environment.environment.ambient_light_energy=.65;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.4;stage.add_child(light)
	var structures=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures)
	if not structures.prepare():quit(1);return
	for catalog:String in ["furniture","ladder","storage","window","door","guardrail","fence"]:load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
	var placement=ClassDB.instantiate("NativePrefabPlacement")
	var lot:Resource=preload("res://addons/structures/expansion_catalog.gd").asset("house_c1")
	if not placement.place(structures.blocks,lot,Vector3i.ZERO,0,structures.model_collections(),[]).get("ok",false):quit(1);return
	var spawn:Vector3=preload("res://addons/world_runtime/introduction_spawn.gd").LOCAL
	structures.blocks.set_focus(spawn);structures.blocks.flush_bakes();structures.set_model_focus(spawn)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=spawn+Vector3.UP*1.65;camera.current=true;stage.add_child(camera)
	camera.look_at(spawn+Vector3(0,1.55,-3))
	var equipment:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(equipment)
	var view:Node3D=equipment.human;view.set_process(false);equipment.equip(0)
	view.animation_player.add_animation_library("wakeup_review",load("res://reviews/player_wakeup/Human.wakeup.res"))
	var canvas:=CanvasLayer.new();stage.add_child(canvas);var label:=Label.new();canvas.add_child(label);label.position=Vector2(28,22);label.add_theme_font_size_override("font_size",22)
	view.animation_player.play("wakeup_review/FP_Wake_Confused_Review",0);view.animation_player.advance(0)
	for warmup in 15:await process_frame
	for frame in 150:
		if frame<132:view.animation_player.seek(frame/30.0,true);view.animation_player.advance(0)
		else:
			if frame==132:
				equipment.equip(1)
				view.animation_player.play(view.clips[view.active_clip],.6)
			view.animation_player.advance(1.0/30)
		label.text="TERRAFOREST / WAKE-UP ANIMATION PROPOSAL\nFirst person · %.1f / 5.0 seconds · approval required"%(frame/30.0)
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.save_png(folder.path_join("frames/%04d.png"%frame))
		if frame in [20,48,78,108,149]:image.save_png(folder.path_join("pose_%03d.png"%frame))
	print("PLAYER_WAKEUP_REVIEW frames=150 duration=5 selected_item=",equipment.current);stage.free();quit()
