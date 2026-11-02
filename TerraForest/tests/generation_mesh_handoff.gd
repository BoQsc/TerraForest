# SPDX-License-Identifier: 0BSD
extends SceneTree
const Handoff=preload("res://addons/world_runtime/generation_mesh_handoff.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var backend=load("res://addons/volumetric_terrain/terrain_backend.gd").new()
 backend.native=ClassDB.instantiate("TerrainCore")
 backend.collision_recipes=ClassDB.instantiate("NativeTerrainCollision")
 backend.disk_cache.enabled=false;backend.world_generator=5
 backend.native.execute(Codec.command(6,[1703,5]))
 var center:=Vector3(8,8,8)
 check(Codec.reply_ok(backend.native.execute(Codec.brush(center,center,3,0,true,2))),"Create editable native terrain fixture")
 backend.build_epoch=backend.native.execute(Codec.command(13)).decode_u32(12)
 var key:=Vector3i(0,0,16)
 var job:Dictionary={"key":key,"base":false,"build_epoch":backend.build_epoch,"stamp":0,"epoch":0}
 backend._generation_meshes=Handoff.new()
 backend._execute_mesh(job)
 var original:Dictionary=backend.poll()[0]
 check(not original.has("error") and original.triangles>0 and not original.collision_pieces.is_empty(),"Capture real terrain mesh and native collision recipes")
 var cache:RefCounted=backend._generation_meshes;backend._generation_meshes=null
 var identity:="a".repeat(64)
 check(cache.seal(identity,"native-codec-style",backend.build_epoch),"Completed terrain epoch can be sealed")
 check(not cache.accepts("b".repeat(64),"native-codec-style") and not cache.accepts(identity,"changed-style"),"Changed checkpoint or renderer cannot reuse cached geometry")
 Handoff.publish(cache)
 check(Handoff.consume()==cache and Handoff.consume()==null,"Handoff transfers ownership once")
 backend.snapshot_id=identity;backend.cache_valid=true;backend._startup_meshes=cache
 backend._execute_mesh(job)
 var reused:Dictionary=backend.poll()[0]
 check(reused.get("handoff_cached",false) and reused.arrays==original.arrays,"Verified handoff reuses exact mesh attributes and indices")
 check(reused.collision_pieces==original.collision_pieces and cache.rows.is_empty() and cache.bytes==0,"Exact collision recipes survive transfer and consumed payload is released")
 cache.remember(key,original,backend.build_epoch);cache.seal(identity,"native-codec-style",backend.build_epoch)
 backend.snapshot_id="b".repeat(64);backend._startup_meshes=cache
 backend._execute_mesh(job)
 check(not backend.poll()[0].get("handoff_cached",false),"Backend reconstructs when checkpoint identity differs")
 backend.snapshot_id=identity;backend._startup_meshes=cache;backend.cache_valid=false
 check(Codec.reply_ok(backend.native.execute(Codec.brush(center,center,2,0,false,2))),"Edit native terrain after cache creation")
 backend._execute_mesh(job)
 var changed:Dictionary=backend.poll()[0]
 check(not changed.get("handoff_cached",false) and changed.arrays!=original.arrays,"Invalidated terrain reconstructs changed geometry instead of replaying saved meshes")
 backend._generation_meshes=Handoff.new();backend.cache_valid=true
 job.key=Vector3i(0,0,64);backend._execute_mesh(job)
 var column:Dictionary=backend.poll()[0]
 check(not column.has("error") and column.has("bricks") and not column.bricks.is_empty(),"Capture owned-column terrain with child meshes")
 var column_cache:RefCounted=backend._generation_meshes;backend._generation_meshes=null
 column_cache.seal(identity,"native-codec-style",backend.build_epoch)
 backend._startup_meshes=column_cache;backend._execute_mesh(job)
 var column_reused:Dictionary=backend.poll()[0]
 check(column_reused.get("handoff_cached",false) and column_reused.bricks==column.bricks,"Owned columns retain exact child arrays, bounds and collision recipes")
 var bounded:=Handoff.new()
 bounded.remember(key,{"bytes":Handoff.LIMIT_BYTES+1},1)
 check(bounded.rows.is_empty(),"Oversized handoff falls back without retaining payload")
 bounded.remember(key,original,1);bounded.remember(Vector3i(16,0,16),original,2)
 check(not bounded.rows.has(key) and not bounded.seal(identity,"contract",1),"New terrain epoch discards older mesh payloads and rejects stale sealing")
 backend.native=null;backend.collision_recipes=null
 print("GENERATION_MESH_HANDOFF checks=",checks," failures=",failures)
 quit(1 if failures else 0)
