# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("293947")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.4;stage.add_child(light)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.68,0);camera.current=true;stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	var view:Node3D=tools.human;view.set_process(false);tools.equip(0);tools.place()
	DirAccess.make_dir_recursive_absolute("res://reports/human_placement/preview_frames")
	for frame in 57:
		view.animation_player.play(view.clips.FP_Place_Relaxed,0)
		view.animation_player.seek(float(frame%29)/30.0,true)
		view.animation_player.pause();view.animation_player.advance(0)
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		image.save_png("res://reports/human_placement/preview_frames/%03d.png"%frame)
		if frame==13:image.save_png("res://reports/human_placement/preview.png")
	stage.free();print("HUMAN_PLACEMENT_PREVIEW frames=57");quit()
