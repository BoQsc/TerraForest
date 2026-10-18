# SPDX-License-Identifier: 0BSD
extends "res://tests/enclosed_settlement_walk.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"prepared world loads"):await done();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[2].position
 game.teleport(center+Vector3(15,0,-25))
 if not check(await wait_for(func():return not game.loading_active,60),"eastern workshops stream"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var visited:=0
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
  if Vector2(pose.origin.x-center.x,pose.origin.z-center.z).length()>100:continue
  var start:Vector3=pose*Vector3(0.5,0,3.5)
  var from:=start+Vector3.UP*5;var to:=start-Vector3.UP*10
  if not check(await wait_for(func():return not game._terrain_pick(from,to).is_empty(),8),"workshop approach surface"):continue
  start.y=game._terrain_pick(from,to).position.y+0.05
  aim(start,pose*Vector3(0.5,1,0))
  game.yaw=pose.basis.get_euler().y;game.player.rotation.y=game.yaw;game.pitch=0;game.camera.rotation=Vector3.ZERO
  game.terrain.focus=start;game.structures.blocks.set_focus(pose.origin);game.structures.set_model_focus(pose.origin)
  if not check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(pose.origin-Vector3(20,3,20),Vector3(40,12,40)))) ,"workshop collision ready"):continue
  await walk(90)
  var local:Vector3=pose.affine_inverse()*game.player.position
  check(local.z>0 and local.z<1.5 and absf(local.y)<0.25,"stairs reach closed workshop door")
  game.camera.look_at(pose*Vector3(0.5,1,0));use()
  if not check(game.doors.state.is_open(id),"E opens workshop door"):continue
  for tick in 15:await physics_frame;await process_frame
  await walk(165)
  local=pose.affine_inverse()*game.player.position
  print("WORKSHOP_WALK local=",local)
  check(local.z< -11 and absf(local.y)<0.25 and game.player.is_on_floor(),"player walks through workshop into rear stores")
  game.camera.look_at(pose*Vector3(3,1,-12))
  for tick in 30:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/workshop_interior_%d.png"%visited)
  game.camera.global_position=pose*Vector3(12,9,15);game.camera.look_at(pose*Vector3(0,2,-4))
  for tick in 30:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/workshop_exterior_%d.png"%visited)
  visited+=1
 check(visited==2,"both integrated workshops visited")
 await done()
func done()->void:
 print("REGIONAL_WORKSHOP_WALK failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
