# SPDX-License-Identifier: 0BSD
extends "res://tests/northern_tower_walk.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[3].position
 var expected:Vector3=center+Vector3(25,1,-43.5)
 game.teleport(expected+Vector3(0,0,-8))
 if not check(await wait_for(func():return not game.loading_active,45),"shop street residency ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var door_id:int=0;var pose:=Transform3D.IDENTITY
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  if p.size()!=12:continue
  var origin:=Vector3(p[3],p[7],p[11])
  if origin.distance_to(expected)<2:
   door_id=id;pose=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),origin);break
 if not check(door_id>0,"saved shop entrance found after residency"):await done();return
 var start:Vector3=pose*Vector3(0.5,0,8)
 await wait_for(func():return not game._terrain_pick(start+Vector3.UP*6,start-Vector3.UP*8).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(start+Vector3.UP*6,start-Vector3.UP*8)
 if not check(not hit.is_empty(),"connected cross-street surface"):await done();return
 start.y=hit.position.y+0.05
 aim(start,pose*Vector3(0.5,1,0))
 if not check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(expected-Vector3(14,3,14),Vector3(28,20,28)))),"shop collision ready"):await done();return
 if not check(await go(pose,Vector3(0.5,0,0.8)),"walk street and approach to closed shop door"):await done();return
 game.camera.look_at(pose*Vector3(0.5,1,0));use()
 if not check(game.doors.state.is_open(door_id),"open shop through gameplay interaction"):await done();return
 for i in 15:await physics_frame
 for target:Vector3 in [Vector3(0.5,0,-3),Vector3(0.5,0,-8),Vector3(0.5,0,-13),Vector3(0.5,0,-8),Vector3(0.5,0,-3),Vector3(0.5,0,0.8)]:
  if not check(await go(pose,target),"continuous shop route "+str(target)):await done();return
 # Return to street grade; no teleports after the initial street start.
 var exit_target:Vector3=pose.affine_inverse()*start;exit_target.y-=0.05
 check(await go(pose,exit_target),"return to cross street on foot")
 await done()
func done()->void:
 var file:=FileAccess.open("res://reports/village_shop_walk.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"trace":trace},"  "));file.close()
 print("VILLAGE_SHOP_WALK failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
