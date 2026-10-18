# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active or game.terrain.backend.world_generator!=11:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[game.terrain.backend.world_seed,11]))
 var data:PackedByteArray=core.execute(Codec.command(25))
 var entrance:=Vector3(data.decode_float(24),data.decode_float(28)-5,data.decode_float(32))
 var at:=24+2*28
 var chamber:=Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8))
 game.teleport(entrance+Vector3.UP*.1)
 deadline=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 if "--mine-access-check" in OS.get_cmdline_user_args():
  var token:int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
  var replies:Array=[]
  var receive:=func(id:int,points:PackedVector3Array,normals:PackedVector3Array,_epoch:int,_revision:int):
   if id==token:replies.append({"points":points,"normals":normals})
  game.terrain.surface_batch_ready.connect(receive)
  var points:=PackedVector3Array([entrance+Vector3(10,0,0),entrance+Vector3(14,0,-25),entrance+Vector3(7,0,-50),entrance+Vector3(27,0,0)])
  var accepted:bool=game.terrain.request_surface_batch(points,token)
  deadline=Time.get_ticks_msec()+20000
  while replies.is_empty() and Time.get_ticks_msec()<deadline:
   await process_frame
   if not accepted:accepted=game.terrain.request_surface_batch(points,token)
  game.terrain.surface_batch_ready.disconnect(receive)
  var clear:bool=not replies.is_empty() and replies[0].normals.size()==4
  if clear:
   for i in 3:clear=clear and replies[0].normals[i].length_squared()<.01
   clear=clear and replies[0].normals[3].y>.5
  print("PASS " if clear else "FAIL ","mine access rejects vegetation roots while adjacent ground remains eligible")
  if not clear:quit(1);return
 game.set_physics_process(false);game.fly=false;game.needs_floor_spawn=false
 game.player.position=entrance+Vector3.UP*.1;game.player.velocity=Vector3.ZERO
 game.headlamp.visible=true
 game.camera.position=Vector3(0,1.6,0)
 game.camera.global_position=entrance+Vector3(18,8,16)
 game.camera.look_at(entrance+Vector3(-10,2,0))
 for frame in 120:await process_frame
 await RenderingServer.frame_post_draw
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--mine-screenshot="):root.get_texture().get_image().save_png(arg.trim_prefix("--mine-screenshot="))
 game.camera.position=Vector3(0,1.6,0)
 game.camera.look_at(chamber+Vector3.UP*1.6)
 var failed:=false;var grounded:=0;var ticks:=0
 for target:Vector3 in [chamber,entrance]:
  deadline=Time.get_ticks_msec()+60000
  while game.player.position.distance_to(target)>1 and Time.get_ticks_msec()<deadline:
   await physics_frame
   var direction:Vector3=target-game.player.position;direction.y=0
   if direction.length()>0.1:direction=direction.normalized()
   game.terrain.focus=game.player.position
   if game.loading_active:continue
   game.player.velocity=game.movement.walking_velocity(direction,game.player.velocity,1.0/60,true,game.player.is_on_floor(),false)
   game.movement.move_grounded(game.player,1.0/60)
   ticks+=1
   if game.player.is_on_floor():grounded+=1
   if ticks%600==0:print("MINE_WALK_PROGRESS pos=",game.player.position," target=",target)
   if game.player.position.y<chamber.y-3:failed=true;break
  var reached:bool=game.player.position.distance_to(target)<=1
  print("PASS " if reached else "FAIL ","player reaches cave waypoint ",target," actual=",game.player.position)
  failed=failed or not reached
  if failed:break
 print("MINE_WALK_WORLD failures=",1 if failed else 0," physics_ticks=",ticks," grounded=",grounded)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failed else 0)
