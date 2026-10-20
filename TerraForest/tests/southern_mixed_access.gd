# SPDX-License-Identifier: 0BSD
extends "res://tests/northern_tower_walk.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 game.teleport(center)
 if not check(await wait_for(func():return not game.loading_active,45),"neighborhood streams"):await done();return
 var doors:Array=[]
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
  if Vector2(pose.origin.x-center.x,pose.origin.z-center.z).length()<120:doors.append({"id":id,"pose":pose})
 if not check(doors.size()==4,"four southern mixed entrances"):await done();return
 game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
 aim(center+Vector3(28,15,32),center+Vector3(0,2,0))
 for tick in 120:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/southern_mixed_overview.png")
 for door:Dictionary in doors:
  var pose:Transform3D=door.pose
  var start:Vector3=pose*Vector3(0.5,0,3.5)
  if not check(await wait_for(func():return not game._terrain_pick(start+Vector3.UP*5,start-Vector3.UP*10).is_empty(),8),"approach surface"):break
  start.y=game._terrain_pick(start+Vector3.UP*5,start-Vector3.UP*10).position.y+0.05
  aim(start,pose*Vector3(0.5,1,0));game.yaw=pose.basis.get_euler().y;game.player.rotation.y=game.yaw;game.pitch=0;game.camera.rotation=Vector3.ZERO
  game.structures.blocks.set_focus(pose.origin);game.structures.set_model_focus(pose.origin)
  if not check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(pose.origin-Vector3(12,3,12),Vector3(24,20,24)))),"entrance collision"):break
  # Staging can trigger a second collision load. Reassert held input per tick,
  # as the continuous-route helper does, rather than losing a single key press.
  await go(pose,Vector3(0.5,0,0.8))
  var local:Vector3=pose.affine_inverse()*game.player.position
  print("MIXED_APPROACH door=",door.id," start=",start," local=",local," world=",game.player.position," loading=",game.loading_active)
  if not (local.z>0 and local.z<1.5 and absf(local.y)<0.25):
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/southern_access_failure.png")
  check(local.z>0 and local.z<1.5 and absf(local.y)<0.25,"ground approach reaches closed door %d"%door.id)
  game.camera.look_at(pose*Vector3(0.5,1,0));use()
  if not check(game.doors.state.is_open(door.id),"door opens %d"%door.id):break
  for tick in 15:await physics_frame;await process_frame
  if not check(await go(pose,Vector3(0.5,0,-1.5)),"walk inside %d"%door.id):break
  if not check(await go(pose,Vector3(0.5,0,0.8)),"walk back outside %d"%door.id):break
  trace.append({"door":door.id,"pose":pose,"passed":true})
 await done()
func done()->void:
 var file:=FileAccess.open("res://reports/southern_mixed_access.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"trace":trace},"  "));file.close()
 print("SOUTHERN_MIXED_ACCESS failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
