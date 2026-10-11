# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("263a35");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.7;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-25,0);scene.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.8;scene.add_child(camera);camera.position=Vector3(0,3,4.5);camera.look_at(Vector3.ZERO)
	var pickups=preload("res://addons/world_runtime/material_pickups.gd").new();scene.add_child(pickups)
	var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	if not pickups.prepare(persistence):push_error("Pickup prepare failed");quit(1);return
	var ids: Array=pickups.ITEMS.keys();ids.sort()
	for i in ids.size():
		var at:=Vector3((i%6)*0.7-1.75,0,(i/6)*0.85-1.3)
		pickups.spawn(ids[i],at)
		var label:=Label3D.new();label.text=pickups.ITEMS[ids[i]];label.font_size=28;label.pixel_size=0.002;label.position=at+Vector3(0,-0.2,0.25);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;scene.add_child(label)
	pickups.update_view(0.1,Vector3.ZERO,true)
	for i in 5:await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/gameplay_item_flow")
	root.get_texture().get_image().save_png("res://reports/gameplay_item_flow/dropped_models.png")
	scene.free();await process_frame;print("DROP_MODEL_VISUAL failures=0");quit()
