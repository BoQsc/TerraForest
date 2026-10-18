# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var started:=Time.get_ticks_msec()
 var refill_seen:=false
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:
  await process_frame
  if game.lakes.water!=null:refill_seen=refill_seen or game.lakes.statistics().fill_active
 if game.loading_active or game.terrain.backend.world_generator!=12:quit(1);return
 var load_ms:=Time.get_ticks_msec()-started
 game.set_physics_process(false);game._clear_motion()
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[game.terrain.backend.world_seed,12]))
 var d:PackedByteArray=core.execute(Codec.command(27))
 var center:=Vector3(d.decode_float(48),d.decode_float(44),d.decode_float(56))
 game.teleport(center+Vector3(72,0,20))
 deadline=Time.get_ticks_msec()+60000
 while (game.loading_active or not game.lakes.statistics().render_ready) and Time.get_ticks_msec()<deadline:await process_frame
 var stats:Dictionary=game.lakes.statistics()
 stats["cached_load_ms"]=load_ms;stats["arrival_ms"]=Time.get_ticks_msec()-started-load_ms;stats["refill_seen"]=refill_seen
 var ok:bool=not game.loading_active and stats.render_ready and stats.ready==4 and not stats.capacity_reached and not stats.fill_active and not refill_seen
 for x in [-50,0,50]:ok=ok and game.lakes.depth_at(center+Vector3(x,-.5,0))>0
 ok=ok and game.lakes.depth_at(center+Vector3(85,-.5,0))==0
 game.set_physics_process(false);game.camera.global_position=center+Vector3(72,15,20);game.camera.look_at(center)
 for frame in 120:await process_frame
 var frames:Array[float]=[]
 var previous:=Time.get_ticks_usec()
 for frame in 180:
  await process_frame
  var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.0);previous=now
 frames.sort();stats["stationary_frame_p95_ms"]=frames[171];stats["stationary_frame_max_ms"]=frames[179]
 var submerged_roots:=0
 var visible_roots:=0
 for packed:Array in game.ground_cover.resident.values():
  for species:Dictionary in packed:
   var poses:PackedFloat32Array=species.transforms
   for i in range(0,poses.size(),12):
    var root_position:=Vector3(poses[i+3],poses[i+7],poses[i+11])
    visible_roots+=1
    if game.lakes.depth_at(root_position+Vector3.UP*.08)>0:submerged_roots+=1
 stats["visible_ground_roots"]=visible_roots;stats["submerged_ground_roots"]=submerged_roots
 ok=ok and visible_roots>0 and submerged_roots==0
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_lake_world.png")
 var file:=FileAccess.open("res://reports/regional_lake_world.json",FileAccess.WRITE);file.store_string(JSON.stringify(stats,"  "));file.close()
 print("REGIONAL_LAKE_WORLD failures=",0 if ok else 1," stats=",JSON.stringify(stats))
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)
