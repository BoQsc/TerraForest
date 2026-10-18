# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func wood()->int:
 var total:=0
 for slot:Dictionary in game.player_hud.inventory.snapshot().slots:
  if slot.item==102:total+=int(slot.count)
 return total
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/woody_bush")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
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
 var owner:=Vector2i(floori(foot.x/32),floori(foot.z/32))
 var cover=game.ground_cover
 var natural_count:=0
 for cell in cover.resident:natural_count+=cover.resident[cell][8].ids.size()
 check(natural_count>0,"woody bushes occur in integrated world")
 var results:Array=[]
 for tool in [1,2,3,4,0]:
  var id:int=cover.removed.add(8,Transform3D(Basis.IDENTITY,foot));cover._dirty[owner]=true
  if not check(id>0 and await wait_for(settled,10),"bush publishes through production support"):break
  for frame in 45:await RenderingServer.frame_post_draw
  check(cover.batches[8].get_ids().has(id),"authored bush rendered")
  game.camera.global_position=foot+Vector3(0,1.8,1.4);game.camera.look_at(foot+Vector3.UP*0.8)
  game.player_hud.equip(maxi(0,tool-1));game.equipped_tool=tool
  for frame in 3:await RenderingServer.frame_post_draw
  if tool==1:root.get_texture().get_image().save_png("res://reports/woody_bush/before.png")
  var t:Dictionary=game.world_attack.target()
  if not check(t.get("id",0)==id and t.get("species",-1)==8,"camera targets woody bush"):break
  var before:=wood()
  var rejected:Dictionary=game.ground_interaction.collect(game.camera.global_position,t.end,game.player_hud.inventory,true)
  check(not rejected.ok and wood()==before,"collect key cannot bypass durability")
  var wear_before:int=game.player_hud.inventory.snapshot().slots[maxi(0,tool-1)].wear
  check(game.world_attack.apply_target(t) and cover.batches[8].get_ids().has(id) and wood()==before,"first hit retains bush without wood reward")
  var damage:PackedByteArray=game.world_attack.durability.capture_storage_snapshot()
  var restored=ClassDB.instantiate("NativeWorldDurability")
  check(restored.restore_storage_snapshot(damage),"half-damaged bush durability restores")
  game.world_attack.durability.restore_storage_snapshot(restored.capture_storage_snapshot())
  check(game.world_attack.apply_target(t) and not cover.batches[8].get_ids().has(id) and wood()==before+1,"second hit removes exact bush and grants one wood")
  if tool!=0:check(game.player_hud.inventory.snapshot().slots[tool-1].wear==wear_before+2,"tool wears once per accepted hit")
  check(not game.ground_interaction.collect(game.camera.global_position,t.end,game.player_hud.inventory,true,null,id).ok and wood()==before+1,"stale target cannot duplicate wood")
  results.append({"tool":tool,"wood_delta":wood()-before})
  if tool==1:
   for frame in 3:await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/woody_bush/after.png")
 var inventory=game.player_hud.inventory
 check(inventory.grant_items(PackedInt64Array([212,1]),inventory.snapshot().revision).ok,"woody bush item registered")
 var placed:Dictionary={}
 for i in 36:
  var point:=foot+Vector3((i%6-3)*0.7,0,(i/6-3)*0.7)
  var start:=point+Vector3.UP*3;var end:=point-Vector3.UP*2
  if game.ground_interaction.placement_probe(8,start,end,inventory,true).ok:
   placed=game.ground_interaction.place(8,start,end,inventory,true);break
 check(placed.get("ok",false),"inventory bush places through gameplay probe")
 if placed.get("ok",false):
  check(await wait_for(settled,10) and cover.batches[8].get_ids().has(placed.id),"placed inventory bush publishes")
 check(preload("res://addons/player_runtime/item_icons.gd").texture(212)!=null and load("res://addons/player_runtime/art/drops/212.res")!=null,"baked icon and dropped model available")
 check(results.size()==5,"all four tools and empty hands covered")
 check(cover.rejected_batches==0 and cover.batches.size()==9,"nine batched species publish without rejection")
 check(root.size==Vector2i(1920,1080),"1080p world check")
 FileAccess.open("res://reports/woody_bush/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"natural_bushes":natural_count,"attacks":results},"  "))
 await done()
