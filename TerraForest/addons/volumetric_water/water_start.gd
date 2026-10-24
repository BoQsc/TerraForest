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
    game.player_hud.equip_item(401)
    if "--water-bucket-review" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
     var shore:Vector3=game.lakes.water.surface_near(center+Vector3(0,-0.75,5.5),2.0)
     if shore.is_finite():
      var aim_target:Vector3=shore+Vector3(0,0.06,-0.6)
      for step in 12:
       var stand:Vector3=shore+Vector3(0,0,1.0+step*0.2)
       var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(stand+Vector3.UP*10,stand-Vector3.UP*10,1))
       if ground.is_empty() or ground.position.y<shore.y-0.1:continue
       var feet:Vector3=ground.position+Vector3.UP*0.05
       var eye:Vector3=feet+Vector3.UP*1.68
       if eye.distance_to(aim_target)>3.4:continue
       game.player.global_position=feet
       var aim:Vector3=aim_target-eye
       game.pitch=atan2(aim.y,Vector2(aim.x,aim.z).length());game.camera.rotation.x=game.pitch;game._clear_motion();break
     var layer:=CanvasLayer.new();game.add_child(layer)
     var guide:=Label.new();guide.position=Vector2(400,24);guide.add_theme_font_size_override("font_size",20);guide.add_theme_color_override("font_shadow_color",Color.BLACK);guide.add_theme_constant_override("shadow_offset_x",2);guide.add_theme_constant_override("shadow_offset_y",2);guide.mouse_filter=Control.MOUSE_FILTER_IGNORE
     guide.text="BUCKET REVIEW · temporary world\nLeft click: collect 1 water unit · Right click: place 1 unit\nOne unit = 1 m³ · Water stays where placed; no flow.\nScoop here, then turn toward dry ground and pour.\nEsc: menu · Changes are discarded on close."
     layer.add_child(guide);game.set_meta("water_bucket_review_ready",true)
    if not game.temporary_world:game.terrain.save_world()
    game._show_lake_notice("Bucket review · disposable world" if game.temporary_world else "Finite lake ready · Bucket: left fill / right pour contents · Esc: Save world")
    queue_free();return
