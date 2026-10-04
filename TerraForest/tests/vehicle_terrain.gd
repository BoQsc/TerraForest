# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60;Engine.physics_ticks_per_second=120
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	var joined: bool="--joined-road-fixture" in OS.get_cmdline_user_args()
	var road_ok: bool
	if joined:
		road_ok=Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(400,182,432),4,4,6)))
		road_ok=Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,182,432),Vector3(400,184,464),4,4,6))) and road_ok
	else: road_ok=Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(400,184,464),4,4,6)))
	if not road_ok:
		push_error("Road construction failed");quit(1);return
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	var regions: Array[PackedVector3Array]=[]
	for x in [384,400]:
		for z in [400,416,432,448]:
			var data: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,160,192,epoch))
			if data.has("error"): push_error(str(data));quit(1);return
			faces.append_array(data.faces)
			if not data.faces.is_empty(): regions.append(data.faces)
	var ground:=Node3D.new();root.add_child(ground)
	# Keep separate region bodies for the joined fixture: a single merged shape
	# would hide physics boundary behavior at the road/region intersection.
	var collision_regions: Array[PackedVector3Array]=regions if joined else [faces]
	for region_faces in collision_regions:
		var body:=StaticBody3D.new();body.collision_layer=1
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(region_faces)
		var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);ground.add_child(body)
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
	var seam_samples: Array[float]=[];var seam_ok:=true;var maximum_step:=0.0
	if joined:
		for i in 33:
			var z:=428.0+i*0.25
			var seam_query:=PhysicsRayQueryParameters3D.create(Vector3(400,186,z),Vector3(400,176,z),1,[car.get_rid()])
			var hit:=root.get_world_3d().direct_space_state.intersect_ray(seam_query)
			if hit.is_empty(): seam_ok=false;continue
			var height: float=hit.position.y
			if not seam_samples.is_empty(): maximum_step=maxf(maximum_step,absf(height-seam_samples[-1]))
			seam_samples.append(height)
			seam_ok=seam_ok and absf(height-(180+(z-400)/16))<0.35
		seam_ok=seam_ok and seam_samples.size()==33 and maximum_step<0.15
	var start: Vector3=car.position;var supported:=0;var minimum_clearance:=1000.0
	var seam_ticks:=0;var seam_supported:=0
	var query:=PhysicsRayQueryParameters3D.create(car.position+Vector3.UP*2,car.position-Vector3.UP*3,1,[car.get_rid()])
	print("GROUND_DIAGNOSTIC ",root.get_world_3d().direct_space_state.intersect_ray(query)," wheel_points=",car._contact_points," wheel_normal=",car._contact_normals)
	var key:=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key);Input.flush_buffered_events()
	var drive_ticks:=390 if joined else 360
	for tick in drive_ticks:
		await physics_frame
		if car.loaded_wheels>=3: supported+=1
		if car.position.z>=428 and car.position.z<=436:
			seam_ticks+=1
			if car.loaded_wheels>=3: seam_supported+=1
		minimum_clearance=minf(minimum_clearance,car.position.y-(180+(car.position.z-400)/16))
		camera.position=car.position+Vector3(9,7,-12);camera.look_at(car.position)
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W
	Input.parse_input_event(release);Input.flush_buffered_events()
	var passed: bool=car.position.is_finite() and car.position.z>432 and car.position.z<460 and absf(car.position.x-400)<0.5 and supported>=drive_ticks-30 and minimum_clearance>0.2
	if joined: passed=passed and seam_ok and car.position.z>436 and seam_ticks>0 and seam_supported>=seam_ticks*0.9
	var report:={"passed":passed,"joined":joined,"start":start,"end":car.position,"supported_ticks":supported,"ticks":drive_ticks,"min_chassis_clearance":minimum_clearance,"speed_kph":car.speed_kph,"triangles":faces.size()/3,"seam_heights":seam_samples,"max_seam_step":maximum_step,"seam_ticks":seam_ticks,"seam_supported":seam_supported,"scope":"Resident native collision; straight collinear road sections at 6.25 percent grade. Not streamed high-speed travel or arbitrary junction qualification."}
	report["collision_bodies"]=collision_regions.size()
	print("VEHICLE_TERRAIN ",report)
	var file:=FileAccess.open("res://reports/vehicle_terrain_joined.json" if joined else "res://reports/vehicle_terrain.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_terrain_joined.png" if joined else "res://reports/vehicle_terrain.png")
	car.free();ground.free();visual.free();camera.free();light.free();environment.free()
	quit(0 if passed else 1)
