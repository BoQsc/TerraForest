# SPDX-License-Identifier: 0BSD
# Acceptance fixture: reachable destinations must be reached around static obstacles.
# A failure is retained as a navigation baseline, never relabelled as success.
extends SceneTree
var failures:=0
var checks:=0
var actors: Node3D
var elapsed:=0.0
var frames:=0
var peak_tick_us:=0
var peak_active:=0
var peak_route_work:=0
var peak_planning_us:=0
var route_ready_seconds: Array=[-1.0,-1.0]
var traces: Array=[[],[]]
var handles: Array[int]=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(parent: Node3D,at: Vector3,size: Vector3,color: Color,layer: int=1) -> void:
	var body:=StaticBody3D.new();body.position=at;body.collision_layer=layer
	var shape:=BoxShape3D.new();shape.size=size
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider)
	var visible:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size
	var material:=StandardMaterial3D.new();material.albedo_color=color;mesh.material=material;visible.mesh=mesh;body.add_child(visible);parent.add_child(body)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var scene:=Node3D.new();root.add_child(scene)
	box(scene,Vector3(0,-0.5,2),Vector3(16,1,16),Color("34473d"))
	box(scene,Vector3(0,1.5,0),Vector3(0.6,3,4),Color("936c49"),2)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("17252c");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.65;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);scene.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=13;scene.add_child(camera);camera.position=Vector3(-8,12,13);camera.look_at(Vector3(0,0,2))
	var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors)
	check(actors.prepare(persistence) and actors.enable(2),"existing actor world and bounded activation initialize")
	if actors.pool==null:scene.free();quit(1);return
	var goals: Array[Vector3]=[Vector3(3,0.93,0),Vector3(3,0.93,5)]
	for i in 2:
		var id: int=actors.spawn(Vector3(-3,0.93,i*5));handles.append(actors.store.resolve_identity(id));actors.orders.set_target(id,goals[i])
		box(scene,goals[i]-Vector3.UP*0.87,Vector3(0.7,0.08,0.7),Color("75dba1"),0)
		var label:=Label3D.new();label.text="AROUND WALL" if i==0 else "CLEAR ROUTE";label.position=goals[i]+Vector3.UP*0.6;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=40;scene.add_child(label)
	for i in 3:await physics_frame
	var delta:=1.0/Engine.physics_ticks_per_second
	while elapsed<6.0:
		await physics_frame
		var begin:=Time.get_ticks_usec()
		actors.update_simulation(delta,Vector3(0,1,2),true,func(_bounds: AABB):return true)
		peak_tick_us=maxi(peak_tick_us,Time.get_ticks_usec()-begin);peak_active=maxi(peak_active,int(actors.status.get("active",0)))
		peak_route_work=maxi(peak_route_work,int(actors.simulation_status.route_work))
		peak_planning_us=maxi(peak_planning_us,int(actors.simulation_status.route_planning_us))
		for i in 2:
			if route_ready_seconds[i]<0 and actors.pool.navigation_status(handles[i]).state in ["following","arrived"]:route_ready_seconds[i]=elapsed
		frames+=1;elapsed+=delta
		if frames%12==0:
			for i in 2:
				var p: Vector3=actors.store.get_position(handles[i]);traces[i].append([p.x,p.y,p.z])
	var clear_end: Vector3=actors.store.get_position(handles[1]);var wall_end: Vector3=actors.store.get_position(handles[0])
	check(Vector2(clear_end.x,clear_end.z).distance_to(Vector2(3,5))<0.25,"clear-route control reaches destination")
	check(Vector2(wall_end.x,wall_end.z).distance_to(Vector2(3,0))<0.25,"actor reaches reachable destination around wall")
	check(wall_end.y>0.85 and clear_end.y>0.85,"actors retain floor support")
	check(peak_active<=2,"active collision proxy count stays within declared capacity")
	var clip:=false
	for p in traces[0]:
		if absf(p[0])<0.64 and absf(p[2])<2.34:clip=true
	check(not clip,"observed actor trajectory does not cross solid wall")
	var output="res://reports/actor_navigation";DirAccess.make_dir_recursive_absolute(output)
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/route.png")
	var report={"checks":checks,"failures":failures,"simulation_seconds":elapsed,"physics_ticks":frames,"physics_hz":Engine.physics_ticks_per_second,"active_limit":2,"peak_active":peak_active,"peak_adapter_tick_us":peak_tick_us,"peak_route_work":peak_route_work,"peak_planning_us":peak_planning_us,"route_ready_simulation_seconds":route_ready_seconds,"wall_end":[wall_end.x,wall_end.y,wall_end.z],"clear_end":[clear_end.x,clear_end.y,clear_end.z],"traces":traces,"scope":"Actual actor-world adapter and native activation/movement, static collision wall and floor; bounded local native planner; no main-world streaming, population or thermal qualification"}
	var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	scene.free();await process_frame;print("ACTOR_NAVIGATION checks=",checks," failures=",failures);quit(1 if failures else 0)
