# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var game:Node3D
var failures:=0
var checks:Array=[]
var timings:Dictionary={}
var frames:Array[float]=[]
var gpu_times:Array[float]=[]
var cpu_render_times:Array[float]=[]
var measuring:=false
var previous_frame:=0
var restored_stats:Dictionary={}
func _initialize():
 process_frame.connect(record_frame)
 call_deferred("run")
func record_frame():
 var now:=Time.get_ticks_usec()
 if measuring and previous_frame>0:
  frames.append((now-previous_frame)/1000.0)
  gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  cpu_render_times.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
 previous_frame=now
func check(ok:bool,label:String):
 checks.append({"name":label,"pass":ok});print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func ready_world() -> bool:
 var deadline:=Time.get_ticks_msec()+20000
 while Time.get_ticks_msec()<deadline:
  if not game.loading_active and game.terrain.world_ready and not game.terrain.pending_edit:return true
  await process_frame
 return false
func wait_water(seconds:float=12.0,settled:bool=false) -> bool:
 var deadline:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:
  var s:Dictionary=game.lakes.statistics()
  if not game.terrain.pending_edit and s.ready==s.lakes and s.render_ready and (not settled or s.active_cells==0):return true
  await process_frame
 print("WAIT_STATE ",game.lakes.statistics())
 return false
func run():
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60;game.max_fps=60;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(await ready_world(),"Normal combined world loads")
 if failures:await finish();return
 game.fly=true;game.needs_floor_spawn=false;game._clear_motion();game.app_focused=true
 var point:Vector3=game.player.global_position+Vector3(0,0,-18)
 var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*60,point-Vector3.UP*60,1))
 check(not hit.is_empty(),"World terrain supplies lake location")
 if failures:await finish();return
 var center:Vector3=hit.position.floor()
 var start:=Time.get_ticks_msec()
 check(game.create_lake(center)>0,"Ordinary lake authoring uses shallow elongated excavation")
 measuring=true
 check(await wait_water(18.0),"Actual world water builds and publishes")
 timings.cold_water_ms=Time.get_ticks_msec()-start
 print("COLD_STATS ",game.lakes.statistics())
 if failures:await finish();return
 var quantity:int=game.lakes.statistics().water_ml
 var probe:Vector3=center-Vector3(0,2,0)
 check(await wait_water(2.0,true),"Undisturbed lake sleeps with no active water cells")
 var idle_steps:int=game.lakes.statistics().cell_steps
 for frame in 12:await process_frame
 check(game.lakes.statistics().cell_steps==idle_steps,"Sleeping lake performs zero flow cell steps")
 check(quantity>10000 and game.lakes.depth_at(probe)>0,"Lake is visibly filled and swimming query is wet")
 var inventory=game.player_hud.inventory
 check(game.player_hud.equip_item(401),"Gameplay equips normal bucket")
 var slot:int=game.player_hud.active_slot
 game.camera.global_position=probe+Vector3.UP*1.5;game.camera.look_at(probe,Vector3.FORWARD);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 print("INPUT_STATE ",game.session_menu.developer," ",game.equipped_tool," ",game._model_edit_available()," ",Input.mouse_mode," ",game.player_hud.active_item)
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;game._unhandled_input(click);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(inventory.snapshot().slots[slot].item==402 and game.lakes.statistics().water_ml==quantity-1000,"Real bucket left-click conserves lake + inventory water")
 var stale:Dictionary=game.lakes.bucket(probe+Vector3.UP,probe,false,inventory,slot,-1)
 check(not stale.ok and game.lakes.statistics().water_ml==quantity-1000,"Stale bucket action cannot remove or create water")
 if failures:await finish();return
 # A new unrelated hole, outside the authored lake. No lake definition at target.
 var hole:Vector3=center+Vector3(28,0,0)
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(hole+Vector3.UP*60,hole-Vector3.UP*60,1))
 check(not ground.is_empty(),"Separate hole is carved into actual terrain, not empty air")
 if ground.is_empty():await finish();return
 hole=ground.position.floor()
 check(game.terrain.sculpt_sphere(hole,2.0),"Mine a separate hole outside lake definitions")
 check(await ready_world(),"Separate hole terrain edit publishes")
 var target:Vector3=hole-Vector3(0,1,0)
 game.camera.global_position=target+Vector3.UP*1.4;game.camera.look_at(target,Vector3.FORWARD);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 click.button_index=MOUSE_BUTTON_RIGHT;game._unhandled_input(click);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 var deadline:=Time.get_ticks_msec()+6000
 while inventory.snapshot().slots[slot].item!=401 and Time.get_ticks_msec()<deadline:await process_frame
 check(inventory.snapshot().slots[slot].item==401 and game.lakes.statistics().water_ml==quantity,"Real right-click creates water outside lake with exact bucket debit")
 if failures:await finish();return
 var puddle_deadline:=Time.get_ticks_msec()+3000
 while Time.get_ticks_msec()<puddle_deadline and (game.lakes.statistics().active_cells>0 or game.lakes.statistics().pending_regions>0):await process_frame
 var puddle:Vector3=game.lakes.water.surface_near(hole-Vector3(0,1.5,0),3.0)
 check(puddle.is_finite(),"Poured water settles to a queryable surface in the dug hole")
 if not puddle.is_finite():await finish();return
 game.camera.global_position=puddle+Vector3.UP*1.5;game.camera.look_at(puddle,Vector3.FORWARD);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.pitch=-PI/2;game.camera.look_at(puddle,Vector3.FORWARD)
 var puddle_start:Vector3=game.camera.global_position
 var puddle_end:Vector3=puddle_start-game.camera.global_basis.z*3.5
 var puddle_hit:Dictionary=game.structures.blocks.raycast_scene(puddle_start,puddle_end,0xFFFFFFFF,[game.player.get_rid()])
 print("PUDDLE_AIM ",puddle," START ",puddle_start," END ",puddle_end," HIT ",puddle_hit)
 click.button_index=MOUSE_BUTTON_LEFT;game._unhandled_input(click);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(inventory.snapshot().slots[slot].item==402 and game.lakes.statistics().water_ml==quantity-1000,"One-litre puddle can be scooped back through real gameplay")
 if failures:await finish();return
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;click.button_index=MOUSE_BUTTON_RIGHT;game._unhandled_input(click);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 check(inventory.snapshot().slots[slot].item==401 and game.lakes.statistics().water_ml==quantity,"Puddle pour-back conserves the same litre")
 if failures:await finish();return
 # Open an underground outlet connected to the lake's right bank.
 var outlet:Vector3=center+Vector3(13,-4,0)
 var a:Vector3=center+Vector3(6,-2,0)
 check(game.lakes.depth_at(outlet)==0,"Future outlet starts dry")
 start=Time.get_ticks_msec()
 check(game.terrain.edit(Codec.brush(a,outlet,2.0,0,false,1),a,outlet),"Mining beside filled water is accepted through ordinary terrain path")
 check(await ready_world(),"Outlet terrain edit publishes")
 deadline=Time.get_ticks_msec()+10000
 while game.lakes.depth_at(outlet)<=0 and Time.get_ticks_msec()<deadline:await process_frame
 timings.outlet_response_ms=Time.get_ticks_msec()-start
 check(game.lakes.depth_at(outlet)>0,"Water flows into mined outlet in actual world")
 check(game.lakes.statistics().water_ml==quantity,"Mining and flowing conserve every millilitre")
 var outlet_region:=Vector3i((outlet/4.0).floor())
 deadline=Time.get_ticks_msec()+2000
 while Time.get_ticks_msec()<deadline:
  if game.lakes._meshes.has(outlet_region) and game.lakes._meshes[outlet_region].mesh!=null:break
  await process_frame
 check(game.lakes._meshes.has(outlet_region) and game.lakes._meshes[outlet_region].mesh!=null,"Flowing outlet receives a visible regional mesh within 2 seconds")
 var s:Dictionary=game.lakes.statistics();timings.runtime_before_save=s
 var data:PackedByteArray=game.lakes.capture_snapshot()
 check(not data.is_empty() and game.lakes.snapshot_validator().validate_snapshot(data),"Snapshot validates quantities and cached occupancy")
 if not data.is_empty():
  var corrupt:=data.duplicate();corrupt.encode_u64(16,quantity+1)
  check(not game.lakes.snapshot_validator().validate_snapshot(corrupt),"Snapshot rejects inconsistent total quantity")
  check(not game.lakes.snapshot_validator().validate_snapshot(data.slice(0,data.size()-1)),"Snapshot rejects truncated cache without replacing live state")
 check(not game.temporary_world,"Fixture owns a disposable real saved world")
 var saved:Array=[false]
 game.terrain.message_changed.connect(func(message:String):
  if message.begins_with("World saved and verified"):saved[0]=true)
 game.terrain.save_world();deadline=Time.get_ticks_msec()+10000
 while not saved[0] and Time.get_ticks_msec()<deadline:await process_frame
 check(saved[0],"Normal world save publishes terrain, water cache and bucket together")
 if failures:await finish();return
 measuring=false
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 start=Time.get_ticks_msec();game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60;game.max_fps=60;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 game.terrain.snapshot_restored.connect(func(_sections:Dictionary,_epoch:int):restored_stats=game.lakes.statistics())
 check(await ready_world(),"Saved combined world reopens")
 measuring=true
 deadline=Time.get_ticks_msec()+2000
 while Time.get_ticks_msec()<deadline:
  if game.lakes._meshes.has(outlet_region) and game.lakes._meshes[outlet_region].mesh!=null:break
  await process_frame
 check(game.lakes._meshes.has(outlet_region) and game.lakes._meshes[outlet_region].mesh!=null,"Saved outlet surface republishes within 2 seconds")
 timings.reopen_ms=Time.get_ticks_msec()-start
 s=game.lakes.statistics();timings.runtime_reopened=s
 check(s.water_ml==quantity and game.player_hud.inventory.snapshot().slots[slot].item==401,"Disk reopening preserves world and bucket quantity")
 print("REOPEN_STATS ",s)
 timings.at_snapshot_restore=restored_stats
 check(s.cache_hits>0 and restored_stats.get("sampled_nodes",-1)==0 and s.cached_region_rebuilds==0,"Warm load restores cached occupancy with zero cached-region rebuilds")
 check(game.lakes.depth_at(outlet)>0,"Mined outlet remains wet after reopening")
 # Developer removal edits quantities without destroying the lake definition.
 var before:int=s.water_ml
 game.lakes.dev_brush(outlet,true,1.0)
 check(game.lakes.statistics().water_ml<before,"Developer water brush removes water locally")
 for frame in 30:await process_frame
 game.fly=true;game.needs_floor_spawn=false;game.player.global_position=center+Vector3(0,8,14);game.yaw=0;game.pitch=-0.65;game.player.rotation.y=0;game.camera.rotation.x=game.pitch;game._clear_motion()
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/regional_water_world.png")
 await finish()
func finish():
 if not frames.is_empty():
  frames.sort();timings.frame_ms={"p50":frames[int(frames.size()*0.5)],"p95":frames[int(frames.size()*0.95)],"max":frames.back(),"samples":frames.size()}
 gpu_times.sort();cpu_render_times.sort()
 if not gpu_times.is_empty():
  timings.gpu_ms={"p50":gpu_times[int(gpu_times.size()*0.5)],"p95":gpu_times[int(gpu_times.size()*0.95)],"max":gpu_times.back()}
  timings.render_cpu_ms={"p95":cpu_render_times[int(cpu_render_times.size()*0.95)],"max":cpu_render_times.back()}
 timings.hardware=RenderingServer.get_video_adapter_name()
 var file:=FileAccess.open("res://reports/regional_water_world.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":timings},"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("REGIONAL_WATER_WORLD failures=",failures);quit(0 if failures==0 else 1)
