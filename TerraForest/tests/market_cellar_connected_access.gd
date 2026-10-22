# SPDX-License-Identifier: 0BSD
extends "res://tests/regional_connected_access.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world loads"):await done();return
 var location_path:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--cellar-location="):location_path=arg.trim_prefix("--cellar-location=")
 var location:Variant
 if not location_path.is_empty():location=JSON.parse_string(FileAccess.get_file_as_string(location_path))
 else:
  var planner=preload("res://addons/structures/terrain_lot_planner.gd")
  var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
  var core=ClassDB.instantiate("TerrainCore");core.execute(codec.command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,16)
  var north:Dictionary=planner.locate(core,layout.sites[3].position)
  var market:Dictionary=preload("res://addons/structures/central_market.gd").locate(core,layout.sites[0].position,planner.earthworks(north).bounds)
  for lot:Dictionary in market.get("lots",[]):
   if lot.asset.get_meta("cellar_clearance",false):location={"origin":[lot.origin.x,lot.origin.y,lot.origin.z],"grade":lot.survey.grade,"arrival":[lot.entrance.segment.finish.x,lot.entrance.segment.finish.y,lot.entrance.segment.finish.z],"rotation":lot.rotation}
 game.player_hud.set_open(false)

 if not check(location is Dictionary and location.rotation==0,"saved cellar location available"):await done();return
 var center:=Vector3(location.arrival[0],location.arrival[1],location.arrival[2])
 var cottage:=Vector3(location.origin[0],location.grade,location.origin[2])
 game.teleport(center)
 if not check(await wait_for(func():return not game.loading_active,45),"western destination loads"):await done();return
 game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false;game.app_focused=true
 var door:Dictionary={}
 for id:int in game.doors.collection.get_ids():
  var p:PackedFloat32Array=game.doors.collection.get_instance(id)
  var pose:=Transform3D(Basis.IDENTITY,Vector3(p[3],p[7],p[11]))
  if pose.origin.distance_to(cottage+Vector3(0,2,5.5))<0.2:door={"id":id,"pose":pose}
 if not check(not door.is_empty(),"cellar entrance resident"):await done();return
 for point:Vector3 in [center,cottage+Vector3(0.5,0,9)]:
  var reached:=await ground_walk(point);trace.append({"target":point,"position":game.player.position,"reached":reached})
  if not check(reached,"walk cellar approach "+str(point)):await done();return
 game.player_hud.set_open(false)
 game.camera.look_at(cottage+Vector3(0,2,0))
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/market_cellar_connected_approach.png")
 if not check(await go(door.pose,Vector3(0.5,0,0.8)),"walk cottage steps"):await done();return
 game.camera.look_at(door.pose*Vector3(0.5,1,0));use()
 if not check(game.doors.state.is_open(door.id),"open cellar cottage"):await done();return
 for tick in 15:await physics_frame
 if not check(await go(door.pose,Vector3(0.5,0,-1)),"enter cottage"):await done();return
 if not check(await go(door.pose,Vector3(0.5,0,-4)),"walk beside hatch"):await done();return
 if not check(await go(door.pose,Vector3(1.5,0,-4)),"walk to ladder approach"):await done();return
 game.yaw=0;game.player.rotation.y=0;game.camera.rotation=Vector3.ZERO
 game.controls.set_key(KEY_S,true,Time.get_ticks_usec())
 for tick in 360:
  await physics_frame;game._physics_process(1.0/60)
  if game.player.position.y<cottage.y-3.8:break
 game.controls.clear(Time.get_ticks_usec())
 if not check(game.player.position.y<cottage.y-3.8 and game.player.position.y>cottage.y-4.2,"descend from house to cellar"):await done();return
 game.camera.look_at(cottage+Vector3(-1,-2,-2))
 game.headlamp.visible=true
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/market_cellar_connected_room.png")
 game.camera.rotation=Vector3.ZERO
 game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
 for tick in 360:
  await physics_frame;game._physics_process(1.0/60)
  if game.player.position.y>cottage.y+1.8 and game.player.position.z<cottage.z+2:break
 game.controls.clear(Time.get_ticks_usec())
 if not check(game.player.position.y>cottage.y+1.8,"climb back into house"):await done();return
 for point:Vector3 in [Vector3(0.5,0,-4),Vector3(0.5,0,-1),Vector3(0.5,0,0.8)]:
  if not check(await go(door.pose,point),"exit cottage "+str(point)):await done();return
 for point:Vector3 in [cottage+Vector3(0.5,0,9),center]:
  if not check(await ground_walk(point),"return to street "+str(point)):await done();return
 await done()
func done()->void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/market_cellar_connected_access.png")
 FileAccess.open("res://reports/market_cellar_connected_access.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"position":game.player.position,"trace":trace},"  "))
 print("MARKET_CELLAR_CONNECTED_ACCESS failures=",failures," position=",game.player.position)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1 if failures else 0)
