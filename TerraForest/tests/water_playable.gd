# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node3D
var failures:=0
var checks:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks.append({"name":label,"pass":ok});print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func wait_ready(water:bool=false) -> bool:
 var deadline:=Time.get_ticks_msec()+45000
 while Time.get_ticks_msec()<deadline:
  if not game.loading_active and game.terrain.world_ready and not game.terrain.pending_edit:
   if not water or game.lakes.statistics().ready==1:return true
   for entry in game.lakes.descriptions():
    if entry.state=="Failed":print("Water failure: ",entry.reason);return false
  await process_frame
 return false
func run():
 game=load("res://demo/world.tscn").instantiate();root.add_child(game);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(await wait_ready(),"Actual world loads with bucket catalog and all persistence providers")
 if failures:await finish();return
 var point:Vector3=game.player.global_position+Vector3(0,0,-18)
 var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*60,point-Vector3.UP*60,1))
 check(not hit.is_empty(),"Lake target has terrain collision")
 if failures:await finish();return
 var center:Vector3=hit.position.floor()
 var id:int=game.create_lake(center)
 check(id>0,"Author lake in actual world")
 var start:=Time.get_ticks_msec()
 check(await wait_ready(true),"Terrain worker compiles finite lake in actual world")
 print("WATER_BUILD_MS ",Time.get_ticks_msec()-start)
 if failures:await finish();return
 var item:Dictionary=game.lakes._lakes[id]
 var quantity:int=game.lakes.statistics().water_ml
 var probe:Vector3=center-Vector3(0,5,0)
 check(game.lakes.depth_at(probe)>1,"Swimming queries use finite lake")
 var inventory=game.player_hud.inventory
 game.player_hud.equip_item(401)
 var slot:int=game.player_hud.active_slot
 check(not game.session_menu.developer,"Game starts with gameplay toolbelt")
 game.fly=true;game.needs_floor_spawn=false;game._clear_motion();game.app_focused=true
 game.camera.global_position=probe+Vector3.UP*3;game.camera.look_at(probe)
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
 game._unhandled_input(click)
 var result:Dictionary={"ok":inventory.snapshot().slots[slot].item==402}
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(result.ok and inventory.snapshot().slots[slot].item==402 and game.lakes.statistics().water_ml==quantity-1000,"Scooping moves exactly 1 L into the selected bucket")
 for i in 9:check(item.volume.transfer_litre(probe,false,inventory,slot,inventory.snapshot().revision),"Bucket litre %d"%(i+2))
 check(not item.volume.transfer_litre(probe,false,inventory,slot,inventory.snapshot().revision) and game.lakes.statistics().water_ml==quantity-10000,"Full bucket cannot remove more water")
 for i in 9:item.volume.transfer_litre(probe,true,inventory,slot,inventory.snapshot().revision)
 var container=ClassDB.instantiate("NativeContainerStore");container.configure(inventory,1)
 var deposit:Dictionary=container.deposit(1,inventory,slot,1,inventory.snapshot().revision,container.snapshot(1).store_revision)
 check(deposit.ok and container.snapshot(1).slots[0].item==402,"Chest storage preserves bucket quantity")
 var withdrawn:Dictionary=container.withdraw(1,inventory,0,1,inventory.snapshot().revision,container.snapshot(1).store_revision)
 check(withdrawn.ok and game.player_hud.equip_item(402),"Bucket withdraws through normal container inventory")
 slot=game.player_hud.active_slot
 var before:PackedByteArray=inventory.capture_storage_snapshot()
 check(not item.volume.transfer_litre(probe,false,inventory,slot,-1) and inventory.capture_storage_snapshot()==before and game.lakes.statistics().water_ml==quantity-1000,"Stale inventory action leaves both quantities unchanged")
 var water_bytes:PackedByteArray=game.lakes.capture_snapshot()
 check(game.lakes.snapshot_validator().validate_snapshot(water_bytes),"Finite water snapshot validates")
 check(not game.temporary_world,"This test owns a unique real save slot")
 var saved: Array=[false]
 game.terrain.message_changed.connect(func(message:String):
  if message.begins_with("World saved and verified"):saved[0]=true)
 game.terrain.save_world()
 var save_deadline:=Time.get_ticks_msec()+10000
 while not saved[0] and Time.get_ticks_msec()<save_deadline:await process_frame
 check(saved[0],"Normal world save writes terrain, finite water and bucket together")
 if failures:await finish();return
 # Dispose every game object and reopen the real saved world, not in-memory data.
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 game=load("res://demo/world.tscn").instantiate();root.add_child(game);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(await wait_ready(true),"Fresh world instance restores terrain and finite water from disk")
 if failures:await finish();return
 inventory=game.player_hud.inventory
 check(game.lakes.statistics().water_ml==quantity-1000 and inventory.snapshot().slots[slot].item==402,"Reload retains withdrawn water and filled bucket")
 result=game.lakes.bucket(probe+Vector3.UP,probe,true,inventory,slot,inventory.snapshot().revision)
 check(result.ok and game.lakes.statistics().water_ml==quantity and inventory.snapshot().slots[slot].item==401,"Pour restores exactly the withdrawn quantity")
 result=game.lakes.bucket(probe+Vector3.UP,probe,true,inventory,slot,inventory.snapshot().revision)
 check(not result.ok and game.lakes.statistics().water_ml==quantity,"Empty bucket cannot create water")
 check(not game.terrain.sculpt_sphere(probe,1),"Basin editing guard prevents mismatched saved quantities")
 game.lakes.bucket(probe+Vector3.UP,probe,false,inventory,slot,inventory.snapshot().revision)
 var dropped:Dictionary=game.pickups.drop_one(inventory,slot,inventory.snapshot().revision,game.player.global_position)
 check(dropped.ok,"Filled bucket drops through batched normal item path")
 var collected:Dictionary=game.pickups.collect_near(game.player.global_position,inventory,func(_p:Vector3):return true)
 check(collected.ok and game.player_hud.equip_item(402),"Recollecting bucket retains its litre of water")
 game.fly=true;game.needs_floor_spawn=false;game.player.position=center+Vector3(0,5,15);game.yaw=0;game.pitch=-0.65;game.player.rotation.y=0;game.camera.rotation.x=game.pitch;game._clear_motion()
 var deadline:=Time.get_ticks_msec()+10000
 while not game.lakes._lakes[id].scene.statistics().ready and Time.get_ticks_msec()<deadline:await process_frame
 check(game.lakes._lakes[id].scene.statistics().ready,"Updated finite surface publishes in the real world")
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/water_playable.png")
 await finish()
func finish():
 var file:=FileAccess.open("res://reports/water_playable.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_PLAYABLE failures=",failures);quit(0 if failures==0 else 1)
