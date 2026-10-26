# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func wood()->int:
 var total:=0
 for slot:Dictionary in game.player_hud.inventory.snapshot().slots:
  if slot.item==102:total+=int(slot.count)
 return total
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_collect_continuity")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;game.player_view.settings_path="";root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[4].position
 game.teleport(center+Vector3(28,0,32))
 if not check(await wait_for(func():return not game.loading_active,45),"arrival ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 if not check(await wait_for(settled,20),"cover ready"):await done();return
 var foot:Vector3=center+Vector3(28,0,32)
 await wait_for(func():return not game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12).is_empty(),8)
 var hit:Dictionary=game._terrain_pick(foot+Vector3.UP*12,foot-Vector3.UP*12)
 if not check(not hit.is_empty(),"ground hit"):await done();return
 foot=hit.position+Vector3.UP*0.02
 var c=game.ground_cover
 for material in c.foliage_materials:material.set_shader_parameter("wind_strength",0.0)
 var count:=0
 for owner in c.resident:
  var row:Dictionary=c.resident[owner][2]
  for i in row.ids.size():
   var values:PackedFloat32Array=row.transforms;var j:int=i*12
   var point:=Vector3(values[j+3],values[j+7],values[j+11])
   if point.distance_to(foot)>5:continue
   game.camera.global_position=point+Vector3(0,1.7,0.2);game.camera.look_at(point+Vector3.UP*0.15)
   for frame in 3:await RenderingServer.frame_post_draw
   var start:Vector3=game.camera.global_position;var end:Vector3=start-game.camera.global_basis.z*2.5
   var probe:Dictionary=game.ground_interaction.collection_probe(start,end)
   if not probe.ok or probe.hit.id!=row.ids[i]:continue
   var batch=c.batches[2];var group:=Vector3(floorf(point.x/32)*32,floorf(point.y/32)*32,floorf(point.z/32)*32)
   var before:=rendered(batch,group)
   if before.is_empty():continue
   if count==0:root.get_texture().get_image().save_png("res://reports/vegetation_collect_continuity/before.png")
   var clock:=Time.get_ticks_usec()
   var result:Dictionary=game.ground_interaction.collect(start,end,game.player_hud.inventory,true)
   var elapsed:=Time.get_ticks_usec()-clock
   check(result.ok,"real gameplay collection accepted")
   var after:=rendered(batch,group)
   check(after.size()==before.size()-1,"only one visible instance removed immediately")
   var stable:=true
   for key in after:stable=stable and before.has(key) and before[key]==after[key]
   check(stable,"survivor transforms and fade ages unchanged")
   for frame in 3:
    await RenderingServer.frame_post_draw
    check(rendered(batch,group)==after,"survivors remain visible on subsequent frame")
    if count==0:root.get_texture().get_image().save_png("res://reports/vegetation_collect_continuity/after_%d.png"%frame)
   print("COLLECT_USEC ",elapsed);count+=1
   break
  if count>=4:break
 check(count>0,"nearby production vegetation exercised")
 check(c.rejected_batches==0,"no rejected vegetation publication")
 await done()
func rendered(batch:Node,group:Vector3)->Dictionary:
 var result:Dictionary={}
 for child in batch.get_children():
  if child is MultiMeshInstance3D and child.visible and child.position==group:
   for i in child.multimesh.instance_count:
    var transform:Transform3D=child.multimesh.get_instance_transform(i)
    result[str(transform)]=child.multimesh.get_instance_custom_data(i)
 return result
