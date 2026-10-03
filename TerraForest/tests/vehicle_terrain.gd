# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60;Engine.physics_ticks_per_second=120
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	if not Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(400,184,464),4,4,6))):
		push_error("Road construction failed");quit(1);return
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	for x in [384,400]:
		for z in [400,416,432,448]:
			var data: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,160,192,epoch))
			if data.has("error"): push_error(str(data));quit(1);return
			faces.append_array(data.faces)
	var ground:=StaticBody3D.new();ground.collision_layer=1
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var collider:=CollisionShape3D.new();collider.shape=shape;ground.add_child(collider);root.add_child(ground)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in faces: surface.add_vertex(vertex)
	surface.generate_normals()
	var visual:=MeshInstance3D.new();visual.mesh=surface.commit()
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.3,0.34,0.29);visual.material_override=material
	root.add_child(visual)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.2;root.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(0.35,0.5,0.65)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.5
	root.add_child(environment)
	var car=load("res://vehicle_demo/scenes/car.tscn").instantiate();car.position=Vector3(400,182,405);root.add_child(car)
	var camera:=Camera3D.new();camera.far=500;root.add_child(camera);camera.make_current()
	for tick in 120: await physics_frame
	var start: Vector3=car.position;var supported:=0;var minimum_clearance:=1000.0
	var query:=PhysicsRayQueryParameters3D.create(car.position+Vector3.UP*2,car.position-Vector3.UP*3,1,[car.get_rid()])
	print("GROUND_DIAGNOSTIC ",root.get_world_3d().direct_space_state.intersect_ray(query)," wheel_points=",car._contact_points," wheel_normal=",car._contact_normals)
	var key:=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key);Input.flush_buffered_events()
	for tick in 360:
		await physics_frame
		if car.loaded_wheels>=3: supported+=1
		minimum_clearance=minf(minimum_clearance,car.position.y-(180+(car.position.z-400)/16))
		camera.position=car.position+Vector3(9,7,-12);camera.look_at(car.position)
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W
	Input.parse_input_event(release);Input.flush_buffered_events()
	var passed: bool=car.position.is_finite() and car.position.z>432 and car.position.z<460 and absf(car.position.x-400)<0.5 and supported>=330 and minimum_clearance>0.2
	print("VEHICLE_TERRAIN ",{"passed":passed,"start":start,"end":car.position,"supported_ticks":supported,"ticks":360,"min_chassis_clearance":minimum_clearance,"speed_kph":car.speed_kph,"triangles":faces.size()/3})
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_terrain.png")
	car.free();ground.free();visual.free();camera.free();light.free();environment.free()
	quit(0 if passed else 1)
