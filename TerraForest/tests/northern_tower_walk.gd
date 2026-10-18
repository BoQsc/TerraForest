# SPDX-License-Identifier: 0BSD
extends "res://tests/enclosed_settlement_walk.gd"
var trace:Array=[]
func go(pose:Transform3D,target:Vector3)->bool:
 var world:Vector3=pose*target
 for tick in 300:
  var offset:Vector3=world-game.player.position;offset.y=0
  if offset.length()<0.15 and absf(game.player.position.y-world.y)<0.2 and game.player.is_on_floor():
   game.controls.clear(Time.get_ticks_usec());trace.append({"target":world,"position":game.player.position,"ticks":tick});return true
  if offset.length()>0.12:
   game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw;game.camera.rotation=Vector3.ZERO
  game.controls.set_key(KEY_W,offset.length()>0.12,Time.get_ticks_usec())
  await physics_frame;game.app_focused=true;game._physics_process(1.0/60)
 game.controls.clear(Time.get_ticks_usec());trace.append({"target":world,"position":game.player.position,"failed":true});return false
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[3].position
 var doors:Array=[]
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
  if Vector2(pose.origin.x-center.x,pose.origin.z-center.z).length()<120:doors.append({"id":id,"pose":pose})
 if not check(doors.size()==12,"twelve saved northern tower entrances"):await done();return
 doors.sort_custom(func(a:Dictionary,b:Dictionary):return a.pose.origin.distance_squared_to(center)<b.pose.origin.distance_squared_to(center))
 var door:Dictionary=doors[0];var pose:Transform3D=door.pose
 game.teleport(pose*Vector3(0.5,0,3.5))
 if not check(await wait_for(func():return not game.loading_active,45),"tower arrival streams"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var start:Vector3=pose*Vector3(0.5,0,3.5)
 await wait_for(func():return not game._terrain_pick(start+Vector3.UP*5,start-Vector3.UP*10).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(start+Vector3.UP*5,start-Vector3.UP*10)
 if not check(not hit.is_empty(),"street approach surface"):await done();return
 start.y=hit.position.y+0.05;aim(start,pose*Vector3(0.5,1,0))
 game.yaw=pose.basis.get_euler().y;game.player.rotation.y=game.yaw;game.pitch=0;game.camera.rotation=Vector3.ZERO
 game.structures.blocks.set_focus(pose.origin);game.structures.set_model_focus(pose.origin)
 if not check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(pose.origin-Vector3(20,3,20),Vector3(40,18,40)))),"tower collision ready"):await done();return
 await walk(90)
 check((pose.affine_inverse()*game.player.position).z>0,"closed door stops player")
 game.camera.look_at(pose*Vector3(0.5,1,0));use()
 if not check(game.doors.state.is_open(door.id),"E opens saved tower door"):await done();return
 for tick in 15:await physics_frame;await process_frame
 # Tower coordinates relative to the entrance: floor height zero, z offset -8.5.
 var route:Array[Vector3]=[Vector3(0.5,0,-1.5),Vector3(3,0,-1.5),Vector3(3,0,-9.3),Vector3(0.5,0,-9.3),Vector3(0.5,4,-3.9),Vector3(3,4,-3.9),Vector3(3,4,-9.3),Vector3(0.5,4,-9.3),Vector3(0.5,8,-3.9),Vector3(0.5,4,-9.3),Vector3(3,4,-9.3),Vector3(3,4,-3.9),Vector3(0.5,4,-3.9),Vector3(0.5,0,-9.3),Vector3(3,0,-9.3),Vector3(3,0,-1.5),Vector3(0.5,0,-1.5),Vector3(0.5,0,0.8)]
 for target:Vector3 in route:
  if not check(await go(pose,target),"tower waypoint "+str(target)):break
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/northern_tower_walk.png")
 await done()
func done()->void:
 var file:=FileAccess.open("res://reports/northern_tower_walk.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"trace":trace},"  "));file.close()
 print("NORTHERN_TOWER_WALK failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
