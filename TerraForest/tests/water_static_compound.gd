# SPDX-License-Identifier: 0BSD
extends SceneTree
var game
var failures:=0
var save_slot:String=""
var saved_notice:=false
var owns_save:=false
var restore_stats:Dictionary={}
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func amounts(bytes:PackedByteArray)->Dictionary:
 var result:Dictionary={};var at:int=32+bytes.decode_u32(8)
 for region in bytes.decode_u32(12):
  var key:int=bytes.decode_u64(at)
  for i in 512:
   var ml:int=bytes.decode_u64(at+20+i*12)&0x7fffffffffffffff
   if ml:result[str(key)+":"+str(i)]=ml
  at+=9076
 return result
func ready_water()->bool:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  if not game.terrain.pending_edit and game.lakes.statistics().render_ready:return true
  await process_frame
 return false
func run():
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot=water_compound_check_"):save_slot=arg.get_slice("=",1)
 if save_slot.is_empty() or not save_slot.is_valid_identifier() or "--temporary" in OS.get_cmdline_user_args():
  check(false,"Unique persistent test slot required");await finish();return
 var initial_path:=ProjectSettings.globalize_path("user://worlds/"+save_slot+".trw")
 for suffix:String in ["",".bak",".lock"]:
  if FileAccess.file_exists(initial_path+suffix):
   check(false,"Test save slot must not already exist");await finish();return
 owns_save=true
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):
  check(false,"Review world prepared");await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var above:=Vector3(entry.seed.x+3,entry.level+3,entry.seed.z)
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
 check(not ground.is_empty(),"Actual lake floor found")
 if ground.is_empty():await finish();return
 var inventory=game.player_hud.inventory;var slot:int=game.player_hud.active_slot
 var from:Vector3=game.camera.global_position;var to:Vector3=from-game.camera.global_basis.z*3.5
 var scoop:Dictionary=game.lakes.bucket(from,to,false,inventory,slot,inventory.snapshot().revision)
 deadline=Time.get_ticks_msec()+5000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 check(inventory.snapshot().slots[slot].water_ml==1000000,"Full bucket collected before compound save")
 if failures:await finish();return
 # Persist a placed unit as well as the lake excavation and held bucket.
 var dry_origin:Vector3=game.player.global_position+Vector3(0,0,10)
 var dry:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(dry_origin+Vector3.UP*30,dry_origin-Vector3.UP*30,1))
 check(not dry.is_empty(),"Ordinary dry ground found for saved placement")
 if dry.is_empty():await finish();return
 var placed:Vector3=dry.position+Vector3.UP*0.03
 game.lakes.bucket(placed+Vector3.UP*2,placed,true,inventory,slot,inventory.snapshot().revision)
 deadline=Time.get_ticks_msec()+5000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 check(inventory.snapshot().slots[slot].water_ml==0 and await ready_water(),"Full unit placed on terrain before disk save")
 check(game.lakes.water.surface_near(placed,2.0).is_finite(),"Saved placement has a published surface")
 game.lakes.bucket(above,above-Vector3.UP*3.5,false,inventory,slot,inventory.snapshot().revision)
 deadline=Time.get_ticks_msec()+5000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 check(inventory.snapshot().slots[slot].water_ml==1000000,"Bucket refilled alongside placed water before save")
 if failures:await finish();return
 var before:=amounts(game.lakes.capture_snapshot())
 var point:Vector3=ground.position-Vector3.UP*0.4
 check(game.terrain.sculpt_sphere(point,1.5),"Ordinary terrain mining beneath lake accepted")
 check(await ready_water(),"Edited terrain and water geometry finish publishing")
 var saved:PackedByteArray=game.lakes.capture_snapshot()
 check(amounts(saved)==before,"Mining does not move water quantities between cells")
 var stats:Dictionary=game.lakes.statistics()
 check(stats.active_cells==0 and stats.cell_steps==0 and stats.pending_vertical==0,"Mining creates no flow or settling work")
 # Persist terrain that intentionally replaces water alongside bucket edits.
 var replacement:=Vector3i(floori(entry.seed.x-3),floori(entry.level)-1,floori(entry.seed.z))
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 var volume_before:int=game.lakes.statistics().water_ml
 check(game.lakes.depth_at(Vector3(replacement)+Vector3.ONE*.5)>0,"Replacement cube starts in occupied water")
 check(game.terrain.set_block(replacement,1),"Terrain cube replaces water before disk save")
 check(await ready_water(),"Terrain replacement and water deletion publish before save")
 check(game.lakes.statistics().water_ml<volume_before,"Terrain replacement deletes water before compound save")
 check(game.lakes.depth_at(Vector3(replacement)+Vector3.ONE*.5)==0,"Replacement cube has no hidden water")
 # Save partial building occupancy through the same compound world archive.
 var construction_targets:Array=[Vector3i(floori(entry.seed.x+6),floori(entry.level)-1,floori(entry.seed.z)),Vector3i(floori(entry.seed.x+8),floori(entry.level)-1,floori(entry.seed.z))]
 var construction_shapes:Array=[3,6]
 var empty_points:Array=[Vector3(.5,.8,.1),Vector3(.9,.9,.9)]
 var solid_points:Array=[Vector3(.5,.8,.9),Vector3(.5,.5,.5)]
 game.construction_inventory.gameplay=false
 for n in construction_targets.size():
  var target:Vector3i=construction_targets[n]
  check(game.lakes.depth_at(Vector3(target)+empty_points[n])>0,"Saved building starts with water in its empty space")
  check(game.construction_inventory.place_block(game.structures.blocks,inventory,target,construction_shapes[n]),"Place partial building before compound save")
  check(await ready_water(),"Building replacement publishes before disk save")
  check(game.lakes.depth_at(Vector3(target)+solid_points[n])==0 and game.lakes.depth_at(Vector3(target)+empty_points[n])>0,"Partial building removes only its solid water volume")
 before=amounts(game.lakes.capture_snapshot())
 game.camera.global_position=above+Vector3(0,1,3);game.camera.look_at(point,Vector3.UP)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_static_compound.png")
 var held_before:PackedByteArray=inventory.capture_storage_snapshot()
 var terrain_before:PackedByteArray=game.terrain.backend.native.execute(Codec.command(4))
 game.terrain.message_changed.connect(func(message:String):
  if message.begins_with("World saved and verified"):saved_notice=true)
 game.terrain.save_world();deadline=Time.get_ticks_msec()+10000
 while not saved_notice and Time.get_ticks_msec()<deadline:await process_frame
 check(saved_notice,"Normal compound save verifies terrain, water and inventory")
 if failures:await finish();return
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 game.terrain.snapshot_restored.connect(func(_sections:Dictionary,_epoch:int):restore_stats=game.lakes.statistics())
 deadline=Time.get_ticks_msec()+20000
 while (game.loading_active or not game.terrain.world_ready) and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active and game.terrain.world_ready and await ready_water(),"Saved combined world reopens and publishes water")
 check(amounts(game.lakes.capture_snapshot())==before,"Compound disk reload preserves every water-cell quantity")
 check(game.lakes.water.surface_near(placed,2.0).is_finite(),"Disk reload republishes the placed water at its saved location")
 check(game.player_hud.inventory.capture_storage_snapshot()==held_before,"Compound disk reload preserves the filled bucket and inventory")
 check(game.terrain.backend.native.execute(Codec.command(4))==terrain_before,"Compound disk reload preserves the mined terrain field exactly")
 check(restore_stats.get("cache_hits",0)>0 and restore_stats.get("sampled_nodes",-1)==0,"Water occupancy restored from cache without resampling")
 check(game.lakes.depth_at(Vector3(replacement)+Vector3.ONE*.5)==0,"Disk reload does not resurrect water inside solid terrain")
 check(restore_stats.get("structure_contact_bytes",0)>0,"Compound disk reload restores prepared building occupancy")
 for n in construction_targets.size():
  var target:Vector3i=construction_targets[n]
  check(game.structures.blocks.get_cell(target)==construction_shapes[n],"Compound disk reload restores the matching building shape")
  check(game.lakes.depth_at(Vector3(target)+solid_points[n])==0 and game.lakes.depth_at(Vector3(target)+empty_points[n])>0,"Disk reload retains water around partial building shape")
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 check(game.terrain.set_block(replacement,0),"Remove saved replacement cube after disk reload")
 check(await ready_water(),"Saved cube removal and water contacts publish")
 check(amounts(game.lakes.capture_snapshot())==before,"Removing reloaded solid does not restore deleted water")
 # Exercise the restored inventory and rendered placement, not just bytes.
 inventory=game.player_hud.inventory
 game.lakes.bucket(above,above-Vector3.UP*3.5,true,inventory,slot,inventory.snapshot().revision)
 deadline=Time.get_ticks_msec()+5000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 check(inventory.snapshot().slots[slot].water_ml==0 and await ready_water(),"Reloaded full bucket pours back into lake")
 var top:Vector3=game.lakes.water.surface_near(placed,2.0)
 check(top.is_finite(),"Reloaded placed water remains targetable")
 if top.is_finite():
  game.lakes.bucket(top+Vector3.UP*2,top-Vector3.UP*0.5,false,inventory,slot,inventory.snapshot().revision)
  deadline=Time.get_ticks_msec()+5000
  while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
  check(inventory.snapshot().slots[slot].water_ml==1000000 and await ready_water(),"Reloaded placement fills one whole bucket")
  check(not game.lakes.water.surface_near(placed,2.0).is_finite(),"Scoop removes reloaded placement without a stale surface")
 var file:=FileAccess.open("res://reports/water_static_compound.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"restore_statistics":restore_stats,"slot":save_slot},"  "));file.close()
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 if owns_save:
  var path:=ProjectSettings.globalize_path("user://worlds/"+save_slot+".trw")
  for suffix:String in ["",".bak",".lock"]:
   if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
 print("WATER_STATIC_COMPOUND failures=",failures);quit(failures)
