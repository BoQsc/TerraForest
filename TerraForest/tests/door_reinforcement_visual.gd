# SPDX-License-Identifier: 0BSD
extends SceneTree

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	run.call_deferred()

func run()->void:
	var output:="res://reports/door_reinforcement"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--door-output="):output=arg.trim_prefix("--door-output=")
	var structures=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	var door:Dictionary=preload("res://addons/structures/door_catalog.gd").register(structures)
	var collection:Node3D=door.collection
	var locks=preload("res://addons/structures/door_locks.gd").new()
	for stage in 4:
		collection.upsert_instances(PackedInt64Array([stage+1]),PackedFloat32Array([1,0,0,stage*1.6,0,door.scale.y,0,0,0,0,1,0]))
		if stage>0:locks.seed(stage+1,180,1703);locks.damage(stage+1,(3-stage)*60)
		var label:=Label3D.new();label.text=["Unlocked","Last board","Damaged","Reinforced"][stage];label.font_size=40;label.pixel_size=.0025;label.position=Vector3(stage*1.6+.5,2.35,.2);root.add_child(label)
	var visual=preload("res://addons/structures/door_reinforcement.gd").new();root.add_child(visual)
	visual.configure(collection,locks,preload("res://addons/structures/door_catalog.gd").builtin_definition().bounds)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.17,.20,.22)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.8,.85,1);environment.environment.ambient_light_energy=.7;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-35,0);sun.shadow_enabled=true;root.add_child(sun)
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);floor_mesh.mesh=plane;root.add_child(floor_mesh)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=46
	DirAccess.make_dir_recursive_absolute(output)
	var views:Dictionary={"front":Vector3(2.9,2.6,9),"rear":Vector3(2.9,2.4,-9),"detail":Vector3(6.9,1.7,2.2)}
	for name:String in views:
		camera.position=views[name];camera.look_at(Vector3(5.3,1.1,0) if name=="detail" else Vector3(2.9,1.1,0))
		for frame in 24:await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(output.path_join(name+".png"))!=OK:quit(1);return
	structures.free();visual.free()
	print("DOOR_REINFORCEMENT_VISUAL failures=0");quit()
