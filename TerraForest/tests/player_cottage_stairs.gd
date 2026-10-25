# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func box(at: Vector3,size: Vector3) -> StaticBody3D:
 var body=StaticBody3D.new();body.collision_layer=2;body.position=at
 var shape=BoxShape3D.new();shape.size=size
 var collider=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);root.add_child(body);return body
func _initialize():run.call_deferred()
func run():
 var world=ClassDB.instantiate("NativeBlockWorld");root.add_child(world);world.set_collision_radius(48);world.set_cells(load("res://addons/structures/prefabs/brick_cottage.tres").get_records());world.flush_bakes()
 var floor_body=StaticBody3D.new();floor_body.collision_layer=1;root.add_child(floor_body);floor_body.position=Vector3(0,-.5,2)
 var floor_shape=BoxShape3D.new();floor_shape.size=Vector3(24,1,24);var floor_collider=CollisionShape3D.new();floor_collider.shape=floor_shape;floor_body.add_child(floor_collider)
 var motor=ClassDB.instantiate("NativePlayerMovement")
 var player=CharacterBody3D.new();player.collision_mask=7;player.collision_layer=8;player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48.0);player.floor_constant_speed=true;player.safe_margin=.004;player.max_slides=8;player.wall_min_slide_angle=0
 var shape=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8
 var collider=CollisionShape3D.new();collider.shape=shape;collider.position.y=.9;player.add_child(collider);root.add_child(player)
 for i in 3:await physics_frame
 for mode in [{"rate":60,"speed":5.5},{"rate":60,"speed":9.9},{"rate":120,"speed":5.5},{"rate":120,"speed":9.9},{"rate":60,"speed":2.5}]:
  Engine.physics_ticks_per_second=mode.rate
  var sprint: bool=mode.speed==9.9
  player.position=Vector3(.5,.03,9);player.velocity=Vector3.ZERO
  var steps=0;var grounded=0
  for i in mode.rate*5:
   await physics_frame
   var direction=Vector3.FORWARD if player.position.z>2.0 else Vector3.ZERO
   player.velocity=motor.walking_velocity(direction,player.velocity,1.0/Engine.physics_ticks_per_second,sprint,player.is_on_floor(),false)
   if mode.speed==2.5:player.velocity.z=direction.z*2.5
   if motor.move_grounded(player,1.0/Engine.physics_ticks_per_second):steps+=1
   if player.is_on_floor():grounded+=1
   if player.position.z<=2.0 and player.position.y>.95 and player.is_on_floor():break
  print("PLAYER_STAIR mode=",mode," end=",player.position," steps=",steps," grounded_ticks=",grounded," normal=",player.get_floor_normal())
  check(player.position.z<2.2 and player.position.y>.95 and player.position.y<1.1,str(mode)+" climbs unchanged cottage stairs and doorway")
 Engine.physics_ticks_per_second=60
 var barrier=box(Vector3(9,.5,5),Vector3(2,1,2))
 player.position=Vector3(9,.03,8);player.velocity=Vector3.ZERO
 for i in 90:
  await physics_frame
  player.velocity=motor.walking_velocity(Vector3.FORWARD,player.velocity,1.0/60,true,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
 check(player.position.z>6 and player.position.y<.31,"one-metre obstacle remains unclimbable")
 barrier.free()
 var tread=box(Vector3(9,.125,5),Vector3(2,.25,2))
 var ceiling=box(Vector3(9,2.05,5.5),Vector3(2,.2,3))
 player.position=Vector3(9,.03,8);player.velocity=Vector3.ZERO
 for i in 90:
  await physics_frame
  player.velocity=motor.walking_velocity(Vector3.FORWARD,player.velocity,1.0/60,false,player.is_on_floor(),false);motor.move_grounded(player,1.0/60)
 check(player.position.z>6 and player.position.y+1.8<1.98,"low ceiling rejects step-up without clipping")
 tread.free();ceiling.free()
 player.free();world.free();floor_body.free();await process_frame
 print("PLAYER_COTTAGE_STAIRS failures=",failures);quit(1 if failures else 0)
