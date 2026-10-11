# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var player: CharacterBody3D
var motor: RefCounted
var ladder: Node3D
func check(ok: bool,label: String) -> void:
	checks+=1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func obstacle(center: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=2
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape
	body.add_child(collision);root.add_child(body);body.position=center;return body
func tick(direction: Vector3,jump: bool=false) -> bool:
	await physics_frame
	player.velocity=motor.walking_velocity(direction,player.velocity,1.0/60,false,player.is_on_floor(),jump)
	var climbing: bool=motor.ladder_velocity(player,direction,1.0/60,jump)
	if climbing: player.move_and_slide()
	else: motor.move_grounded(player,1.0/60)
	return climbing
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	ladder=ClassDB.instantiate("NativeStaticBatch");root.add_child(ladder)
	check(ladder.configure_asset("architecture/wooden_ladder/v1",load("res://addons/structures/prefabs/ladder_model.tres")),"shared ladder asset registered")
	check(ladder.configure_collision(AABB(Vector3(-0.45,0,-0.06),Vector3(0.9,3.6,0.12)),64,128,8),"bounded single-proxy collision configured")
	check(ladder.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])),"stable ladder placement created")
	ladder.set_collision_focus(Vector3.ZERO)
	obstacle(Vector3(0,-0.25,0),Vector3(20,0.5,20))
	obstacle(Vector3(0,2.85,-1.6),Vector3(4,0.3,3))
	player=CharacterBody3D.new();player.collision_mask=2;player.floor_snap_length=0.35;player.safe_margin=0.01
	var shape:=CapsuleShape3D.new();shape.radius=0.34;shape.height=1.8
	var collision:=CollisionShape3D.new();collision.shape=shape;collision.position.y=0.9;player.add_child(collision);root.add_child(player)
	motor=ClassDB.instantiate("NativePlayerMovement");motor.configure_ladders(ladder)
	for i in 15: await physics_frame
	player.position=Vector3(0,0.05,0.55)
	for i in 45: await tick(Vector3.FORWARD)
	check(player.position.y>1.4 and player.position.y<1.7,"W ascends at bounded climbing speed")
	var held: Vector3=player.position
	for i in 20: await tick(Vector3.ZERO)
	check(player.position.distance_to(held)<0.01,"idle holds rung without gravity drift")
	for i in 20: await tick(Vector3.BACK)
	check(player.position.y<held.y-0.6,"S descends")
	for i in 130: await tick(Vector3.FORWARD if player.position.z>-0.8 else Vector3.ZERO)
	check(player.position.z<-.7 and absf(player.position.y-3)<0.08,"climb exits onto three-metre landing using collision")
	print("LANDING ",player.position)
	player.position=Vector3(0,1,0.55);player.velocity=Vector3.ZERO
	check(await tick(Vector3.ZERO,true),"Space detaches from ladder")
	check(player.velocity.z>2.5 and player.velocity.y>4,"jump-off pushes away and upward")
	check(not await tick(Vector3.FORWARD),"detach cooldown prevents immediate recapture")
	for i in 25: await physics_frame
	motor.configure_ladders(ladder)
	player.position=Vector3(0,0.05,0.55);player.velocity=Vector3.ZERO
	var ceiling:=obstacle(Vector3(0,2.6,0.6),Vector3(2,0.2,2))
	for i in 60: await tick(Vector3.FORWARD)
	check(player.position.y<0.75,"low ceiling blocks ascent without teleport")
	ceiling.free()
	var wall:=obstacle(Vector3(0,1.8,0.24),Vector3(2,3.6,0.08))
	player.position=Vector3(0,1,0.7)
	for i in 3: await physics_frame
	check(not motor.ladder_velocity(player,Vector3.FORWARD,1.0/60,false),"wall occludes ladder attachment")
	wall.free()
	var saved: PackedByteArray=ladder.capture_snapshot()
	check(ladder.remove_instances(PackedInt64Array([1])),"ladder removal succeeds")
	player.position=Vector3(0,1,0.55)
	for i in 3: await physics_frame
	check(not motor.ladder_velocity(player,Vector3.FORWARD,1.0/60,false),"removed ladder cannot suspend player")
	check(ladder.restore_snapshot(saved),"saved stable placement restores")
	for i in 15: await physics_frame
	check(motor.ladder_velocity(player,Vector3.FORWARD,1.0/60,false),"restored ladder is climbable")
	ladder.rotation.y=PI/2;player.position=Vector3(0.55,1,0);player.rotation.y=PI/2
	for i in 15: await physics_frame
	check(motor.ladder_velocity(player,Vector3.LEFT,1.0/60,false) and player.velocity.y>1.9,"rotated collection climbs in local facing direction")
	ladder.scale=Vector3(2,1,1)
	for i in 15: await physics_frame
	check(not motor.ladder_velocity(player,Vector3.LEFT,1.0/60,false),"unsupported scaling stays non-climbable")
	ladder.free()
	check(not motor.ladder_velocity(player,Vector3.LEFT,1.0/60,false),"freed collection safely releases controller")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/ladder_traversal.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	print("LADDER_TRAVERSAL ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
