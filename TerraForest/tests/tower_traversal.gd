# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
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
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var module: Resource=load("res://addons/structures/prefabs/tower_floor.tres")
	var assembly: Resource=ClassDB.instantiate("NativeBlockPrefab")
	assembly.compose([module],PackedInt32Array([0,0,0,0,0,0,0,4,0,0,0,0,8,0,0]))
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_focus(Vector3(0,4,0));blocks.set_collision_radius(48)
	check(blocks.place_prefab(assembly,Vector3i.ZERO,0),"three-floor collision fixture placed")
	var bounds:=AABB(Vector3(-2,0,-2),Vector3(5,13,8))
	var deadline:=Time.get_ticks_msec()+10000
	while not blocks.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline: await process_frame
	check(blocks.is_collision_region_ready(bounds),"native stair collision ready")
	var player:=CharacterBody3D.new();player.collision_mask=2;player.floor_snap_length=0.35
	player.floor_max_angle=deg_to_rad(48.0);player.floor_constant_speed=true;player.safe_margin=0.01
	var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8
	collision.shape=capsule;collision.position.y=0.9;player.add_child(collision);root.add_child(player)
	var movement: RefCounted=ClassDB.instantiate("NativePlayerMovement")
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
	var file:=FileAccess.open("res://reports/tower_traversal.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"ascent_position":str(ascent),"scope":"native building collision and player capsule ascent descent and blocked clearance"}));file.close()
	player.free();blocks.free();quit(1 if failures else 0)
