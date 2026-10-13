# SPDX-License-Identifier: 0BSD
extends Node
# Opt-in authoring when the dedicated water slot has no lake. Never modifies
# an existing lake or refills buckets on subsequent visits to this save slot.
var game:Node3D
var stage:=0
var lake_id:=0
var center:=Vector3.ZERO
func _process(_delta:float) -> void:
 if game.loading_active or not game.terrain.world_ready or game.terrain.pending_edit:return
 if stage==0:
  if game.lakes.statistics().lakes>0:
   game._show_lake_notice("Saved water world · equip or craft a bucket · left scoop / right pour");queue_free();return
  var point:Vector3=game.player.global_position+Vector3(0,0,-18)
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*40,point-Vector3.UP*40,1))
  if hit.is_empty():return
  center=hit.position.floor();lake_id=game.create_lake(center);stage=1
  if lake_id==0:game._show_lake_notice("Lake could not be authored here; use Development > Water");queue_free()
  else:game._show_lake_notice("Preparing your finite lake; terrain and water are being built")
 elif stage==1:
  for entry in game.lakes.descriptions():
   if entry.id!=lake_id:continue
   if entry.state=="Failed":game._show_lake_notice(entry.reason);queue_free();return
   if entry.state=="Ready" and game.lakes.statistics().render_ready:
    game.player.global_position=center+Vector3(0,1.0,8.0);game.needs_floor_spawn=false;game.fly=false;game.yaw=0;game.pitch=-0.8;game.player.rotation.y=0;game.camera.rotation.x=game.pitch;game._clear_motion()
    game.player_hud.equip_item(401);game.terrain.save_world()
    game._show_lake_notice("Finite lake ready · Bucket: left fill / right pour contents · Esc: Save world")
    queue_free();return
