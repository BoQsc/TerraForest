# SPDX-License-Identifier: 0BSD
extends SceneTree
var output := "res://reports/bg5_runtime/preview"
func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func pose(position: Vector3, half_turn: bool=false) -> PackedFloat32Array:
	return PackedFloat32Array([-1 if half_turn else 1,0,0,position.x,0,1,0,position.y,0,0,-1 if half_turn else 1,position.z])
func capture(name: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="): output=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new();root.add_child(stage)
	var world = preload("res://addons/structures/structures_world.gd").new();stage.add_child(world)
	var door: Dictionary = preload("res://addons/structures/door_catalog.gd").register(world)
	preload("res://addons/structures/furniture_catalog.gd").register(world)
	preload("res://addons/structures/storage_catalog.gd").register(world)
	var frame_mesh = preload("res://addons/structures/object_mesh.gd").new().load_visual({"source":"door_frame.glb"},"res://mods/bg5_runtime")
	var frame = world.register_model("review/bg5_frame/v1",frame_mesh)
	var door_pose := pose(Vector3(-2,0,0))
	var ok: bool = door.collection.upsert_instances(PackedInt64Array([1]),door_pose) and frame.upsert_instances(PackedInt64Array([1]),door_pose)
	ok = world.model("furniture/shelf/v1").upsert_instances(PackedInt64Array([1]),pose(Vector3(2,0,0))) and ok
	ok = world.model("furniture/table/v1").upsert_instances(PackedInt64Array([1]),pose(Vector3(.2,0,-.4))) and ok
	ok = world.model("furniture/chair/v1").upsert_instances(PackedInt64Array([1]),pose(Vector3(.2,0,-1.6),true)) and ok
	ok = world.model("storage/wooden_chest/v1").upsert_instances(PackedInt64Array([1]),pose(Vector3(-1.25,0,-2.15),true)) and ok
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("28323b")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("c8d6e2")
	environment.environment.ambient_light_energy=.45
	stage.add_child(environment)
	var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,145,0);light.light_energy=.85;light.shadow_enabled=true;stage.add_child(light)
	var fill := DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,-35,0);fill.light_energy=.25;stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(200,200);floor_mesh.mesh=plane
	var material := StandardMaterial3D.new();material.albedo_color=Color("545f65");material.roughness=1;floor_mesh.material_override=material;floor_mesh.position.y=-.02;stage.add_child(floor_mesh)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5.7;stage.add_child(camera)
	camera.position=Vector3(5,3.9,-7);camera.look_at(Vector3(0,1,-.4));camera.current=true
	await capture("closed")
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	ok = hinges.toggle(door.collection,1,AABB()).ok and ok
	await capture("open")
	ok = frame.get_instance(1)==door_pose and ok
	ok = hinges.toggle(door.collection,1,AABB()).ok and door.collection.get_instance(1)==door_pose and ok
	ok = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and ok
	stage.free()
	print("BG5_PREVIEW failures=",0 if ok else 1)
	quit(0 if ok else 1)
