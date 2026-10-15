# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var landing_trace:Array=[]
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func obstacle(center: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=2
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape
	body.add_child(collision);root.add_child(body);body.position=center;return body
func walk(player: CharacterBody3D,movement: RefCounted,direction: Vector3,ticks: int) -> void:
	for tick in ticks:
		await physics_frame
		player.velocity=movement.walking_velocity(direction,player.velocity,1.0/60.0,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60.0)
func walk_to(player: CharacterBody3D,movement: RefCounted,target: Vector3) -> bool:
	for tick in 180:
		var offset:=target-player.position;offset.y=0
		if offset.length()<0.12 and absf(player.position.y-target.y)<0.2 and player.is_on_floor():
			landing_trace.append({"target":target,"position":player.position,"ticks":tick,"arrived":true});return true
		await physics_frame
		player.velocity=movement.walking_velocity(offset.normalized() if offset.length()>=0.12 else Vector3.ZERO,player.velocity,1.0/60.0,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60.0)
	landing_trace.append({"target":target,"position":player.position,"arrived":false})
	return false
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var module: Resource=load("res://addons/structures/prefabs/tower_floor.tres")
	var assembly: Resource=ClassDB.instantiate("NativeBlockPrefab")
	assembly.compose([module],PackedInt32Array([0,0,0,0,0,0,0,4,0,0,0,0,8,0,0]))
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	var structures: Node3D
	if "--furnished" in OS.get_cmdline_user_args():
		blocks.free()
		structures=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
		check(structures.prepare(),"furnished structure world prepared")
		var catalog=preload("res://addons/structures/furniture_catalog.gd")
		check(catalog.register(structures).size()==3,"tower furniture registered")
		check(not preload("res://addons/structures/storage_catalog.gd").register(structures).is_empty(),"tower storage registered")
		check(not preload("res://addons/structures/window_catalog.gd").register(structures).is_empty(),"tower windows registered")
		check(not preload("res://addons/structures/door_catalog.gd").register(structures).is_empty(),"tower entrance registered")
		assembly=catalog.furnished_tower(3);blocks=structures.blocks
		check(assembly!=null and assembly.get_model_attachments().size()==61,"three floors compose furnishings windows and entrance")
	blocks.set_focus(Vector3(0,4,0));blocks.set_collision_radius(48)
	if structures!=null:
		var coordinator=preload("res://addons/player_runtime/construction_inventory.gd").new()
		var inventory=ClassDB.instantiate("NativePlayerInventory")
		check(coordinator.place_prefab(blocks,inventory,assembly,Vector3i.ZERO,0,structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"complete furnished tower placed")
		structures.set_model_focus(Vector3(0,5,0))
		var deadline_models:=Time.get_ticks_msec()+10000
		var all_bounds:=AABB(Vector3(-9,0,-9),Vector3(19,14,19))
		while not structures.is_collision_region_ready(all_bounds) and Time.get_ticks_msec()<deadline_models:await process_frame
		check(structures.is_collision_region_ready(all_bounds),"all furniture and window collision resident")
	else:
		check(blocks.place_prefab(assembly,Vector3i.ZERO,0),"three-floor collision fixture placed")
	var bounds:=AABB(Vector3(-2,0,-2),Vector3(5,13,8))
	var deadline:=Time.get_ticks_msec()+10000
	while not blocks.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline: await process_frame
	check(blocks.is_collision_region_ready(bounds),"native stair collision ready")
	if "--visual" in OS.get_cmdline_user_args():
		var environment:=WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color("91abb8")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.55
		root.add_child(environment)
		var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-45,30,0);sun.shadow_enabled=true
		var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(25,20,32);camera.look_at(Vector3(0,6,0));camera.current=true
	var player:=CharacterBody3D.new();player.collision_mask=2;player.floor_snap_length=0.35
	player.floor_max_angle=deg_to_rad(48.0);player.floor_constant_speed=true;player.safe_margin=0.01
	var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8
	collision.shape=capsule;collision.position.y=0.9;player.add_child(collision);root.add_child(player)
	var movement: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	if structures!=null:
		check(blocks.get_cell(Vector3i(0,12,0))==65 and blocks.get_cell(Vector3i(0,9,0))==0,"sealed roof replaces unused upper flight")
		check(blocks.get_cell(Vector3i(0,5,8))==65 and blocks.get_cell(Vector3i(0,9,8))==65,"upper front openings are enclosed")
		player.position=Vector3(0.5,1.03,9.3)
		await walk(player,movement,Vector3.FORWARD,40)
		check(player.position.z>8.5,"closed entrance blocks approaching player")
		var door: Node3D=structures.model("architecture/wooden_door/v1")
		var hinges: RefCounted=ClassDB.instantiate("NativeHingedDoors")
		check(hinges.toggle(door,door.get_ids()[0],AABB()).ok,"tower entrance opens")
		for frame in 12:await physics_frame
		await walk(player,movement,Vector3.FORWARD,40)
		check(player.position.z<8 and player.is_on_floor(),"player walks through open tower entrance")
	player.position=Vector3(0.5,1.05,-0.8)
	for tick in 20:
		await physics_frame
		player.velocity=movement.walking_velocity(Vector3.ZERO,player.velocity,1.0/60.0,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60.0)
	for tick in 150:
		await physics_frame
		var direction:=Vector3(0,0,1) if player.position.z<4.6 else Vector3.ZERO
		player.velocity=movement.walking_velocity(direction,player.velocity,1.0/60.0,false,player.is_on_floor(),false)
		movement.move_grounded(player,1.0/60.0)
	check(player.position.z>=4.5 and player.position.y>4.9,"capsule walks up flight onto next floor without jumping")
	var ascent: Vector3=player.position
	if "--all-floors" in OS.get_cmdline_user_args():
		var upper:=true
		for target: Vector3 in [Vector3(3,5,4.6),Vector3(3,5,-0.8),Vector3(0.5,5,-0.8),Vector3(0.5,9,4.6)]:
			upper=await walk_to(player,movement,target) and upper
		check(upper and player.position.y>8.9,"player walks the landing and second flight to the third floor")
		var lower:=true
		for target: Vector3 in [Vector3(0.5,5,-0.8),Vector3(3,5,-0.8),Vector3(3,5,4.6),Vector3(0.5,5,4.6)]:
			lower=await walk_to(player,movement,target) and lower
		check(lower,"player returns around landing to first flight")
	await walk(player,movement,Vector3(0,0,-1),70)
	check(player.position.z<0 and player.position.y<1.1,"capsule descends flight back to lower floor")
	var wall:=obstacle(Vector3(3,2.5,1),Vector3(1,3,1))
	player.position=Vector3(3,1.05,-0.8);player.velocity=Vector3.ZERO
	await walk(player,movement,Vector3.ZERO,10)
	await walk(player,movement,Vector3(0,0,1),40)
	check(player.position.z<0.3 and player.position.y<1.1,"step policy cannot climb tall wall")
	wall.free()
	var ceiling:=obstacle(Vector3(0.5,2.95,0.5),Vector3(3,0.1,3))
	player.position=Vector3(0.5,1.05,-0.8);player.velocity=Vector3.ZERO
	await walk(player,movement,Vector3.ZERO,10)
	await walk(player,movement,Vector3(0,0,1),40)
	check(player.position.z<0.3 and player.position.y<1.2,"low ceiling prevents unsafe step-up")
	ceiling.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	if "--visual" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/furnished_tower.png")
	var file:=FileAccess.open("res://reports/tower_traversal.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"ascent_position":str(ascent),"landings":landing_trace,"scope":"native building collision and player capsule ascent descent and blocked clearance"}));file.close()
	player.free()
	if structures!=null:structures.free()
	else:blocks.free()
	quit(1 if failures else 0)
