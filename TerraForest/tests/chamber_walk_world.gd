# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active or game.terrain.backend.world_generator!=9:quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,9]))
 var data:PackedByteArray=core.execute(Codec.command(25))
 var entrance:=Vector3(data.decode_float(24),data.decode_float(28)-5,data.decode_float(32))
 var at:=24+2*28
 var chamber:=Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8))
 game.teleport(entrance+Vector3.UP*.1)
 deadline=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 if game.loading_active:quit(1);return
 game.set_physics_process(false);game.fly=false;game.needs_floor_spawn=false
 game.player.position=entrance+Vector3.UP*.1;game.player.velocity=Vector3.ZERO
 game.headlamp.visible=true
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
   if ticks%600==0:print("CHAMBER_WALK_PROGRESS pos=",game.player.position," target=",target)
   if game.player.position.y<chamber.y-3:failed=true;break
  var reached:bool=game.player.position.distance_to(target)<=1
  print("PASS " if reached else "FAIL ","player reaches cave waypoint ",target," actual=",game.player.position)
  failed=failed or not reached
  if failed:break
 print("CHAMBER_WALK_WORLD failures=",1 if failed else 0," physics_ticks=",ticks," grounded=",grounded)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failed else 0)
