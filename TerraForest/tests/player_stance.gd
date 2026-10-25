extends SceneTree
var failures:=0
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(point:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=point;body.collision_layer=1
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);root.add_child(body);return body
func run()->void:
	var floor:=box(Vector3(0,-.5,0),Vector3(30,1,30))
	var player:=CharacterBody3D.new();player.collision_layer=2;player.collision_mask=1;player.safe_margin=.004;player.max_slides=8;player.wall_min_slide_angle=0;player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true
	var collider:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.34;collider.shape=capsule;collider.position.y=.9;player.add_child(collider);root.add_child(player);player.position.y=.02
	var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for frame in 3:await physics_frame
	check(motor.update_crouch(player,true) and is_equal_approx(capsule.height,1.1) and is_equal_approx(collider.position.y,.55),"crouch lowers capsule without moving the feet")
	var ceiling:=box(Vector3(0,1.5,0),Vector3(3,.3,4))
	for frame in 3:await physics_frame
	check(motor.update_crouch(player,false) and is_equal_approx(capsule.height,1.1),"standing is refused beneath an obstructing ceiling")
	check(motor.walking_velocity(Vector3.FORWARD,Vector3.ZERO,1.0/60,true,true,true,true).is_equal_approx(Vector3(0,0,-2.6)),"crouch limits sprint and prevents jumping into the ceiling")
	for frame in 120:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3.FORWARD,player.velocity,1.0/60,false,player.is_on_floor(),false,true);motor.move_grounded(player,1.0/60)
	check(player.position.z < -4.5 and player.position.y<.1,"crouched player traverses the low passage with normal collision")
	check(not motor.update_crouch(player,false) and is_equal_approx(capsule.height,1.8),"standing resumes after leaving the low ceiling")
	ceiling.free()
	var wall:=box(Vector3(.5,1,0),Vector3(1,2,20))
	player.position=Vector3(-.345,.02,0);player.velocity=Vector3.ZERO
	player.safe_margin=.01;player.max_slides=6;player.wall_min_slide_angle=deg_to_rad(15)
	for frame in 3:await physics_frame
	for frame in 120:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3(1,0,-.15).normalized(),player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
	var legacy_z:float=player.position.z
	player.position=Vector3(-.345,.02,0);player.velocity=Vector3.ZERO;player.safe_margin=.004;player.max_slides=8;player.wall_min_slide_angle=0
	for frame in 3:await physics_frame
	for frame in 120:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3(1,0,-.15).normalized(),player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
	check(player.position.z<-.8 and player.position.x<-.33,"glancing input slides along a wall instead of locking at its edge")
	print("WALL_SLIDE before_z=",legacy_z," after_z=",player.position.z)
	check(player.position.z<legacy_z-.5,"new contact policy improves the reproduced shallow-angle movement lock")
	var wall_end:=player.position
	for frame in 60:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3.LEFT,player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
	check(player.position.x<wall_end.x-4,"player can immediately walk away from sustained wall contact")
	wall.free()
	var pointed:=StaticBody3D.new();pointed.collision_layer=1
	var sharp:=CollisionShape3D.new();var hull:=ConvexPolygonShape3D.new();var points:=PackedVector3Array()
	for height in [0.0,2.0]:
		for point:Vector3 in [Vector3(-.8,0,-.8),Vector3(.8,0,-.8),Vector3(0,0,.8)]:points.append(point+Vector3.UP*height)
	hull.points=points;sharp.shape=hull;pointed.add_child(sharp);root.add_child(pointed)
	player.position=Vector3(0,.02,1.15);player.velocity=Vector3.ZERO
	for frame in 3:await physics_frame
	for frame in 45:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3.FORWARD,player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
	var corner:=player.position
	for frame in 90:
		await physics_frame
		player.velocity=motor.walking_velocity(Vector3(-1,0,.1).normalized(),player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
	check(player.position.distance_to(corner)>3.5 and player.position.y<.1,"player escapes a sharp convex apex by walking aside without destroying or crossing the object")
	pointed.free();player.free();floor.free();await process_frame
	print("PLAYER_STANCE failures=",failures);quit(1 if failures else 0)
