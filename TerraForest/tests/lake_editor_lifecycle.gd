# SPDX-License-Identifier: 0BSD
extends SceneTree
class Terrain extends Node3D:
 signal lake_slice_ready(token: int,status: int,epoch: int,revision: int)
 signal region_invalidated(bounds: AABB)
 var epoch:=1
 var published_revision:=0
 var pending_edit:=false
 var world_ready:=true
 var request: Dictionary={}
 func request_lake_slice(builder: RefCounted,token: int) -> bool:
  request={"builder":builder,"token":token};return true
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var terrain=Terrain.new();root.add_child(terrain)
 var lakes=preload("res://addons/volumetric_water/lake_world.gd").new();lakes.terrain=terrain;root.add_child(lakes);lakes.set_process(false)
 var id: int=lakes.add_lake(Vector3.ZERO,Vector3i(8,6,8),1,3.5,Vector3(2.5,2.5,2.5))
 check(lakes.descriptions()[0].state=="Baking" and not lakes.retry_lake(id),"new lake reports baking and rejects duplicate work")
 lakes._process(0)
 var field=PackedFloat32Array();field.resize(9*7*9);field.fill(-1)
 var status: int=terrain.request.builder.bake_density(field)
 terrain.lake_slice_ready.emit(terrain.request.token,status,1,0)
 check(status==-2 and lakes.descriptions()[0].state=="Failed" and lakes.descriptions()[0].reason.contains("solid"),"real blocked-seed bake exposes actionable failure")
 var snapshot: PackedByteArray=lakes.capture_snapshot()
 terrain.pending_edit=true
 check(not lakes.retry_lake(id),"retry waits for terrain publication")
 terrain.pending_edit=false
 check(lakes.retry_lake(id) and lakes.capture_snapshot()==snapshot,"retry retains authoritative definition and identity")
 lakes._process(0)
 field.clear()
 for z in 9:
  for y in 7:
   for x in 9:field.append(-1.0 if x==0 or x==8 or z==0 or z==8 or y==0 else 1.0)
 status=terrain.request.builder.bake_density(field)
 terrain.lake_slice_ready.emit(terrain.request.token,status,1,0)
 check(status==1 and lakes.descriptions()[0].state=="Ready" and lakes.depth_at(Vector3(2.5,2.5,2.5))>0,"retry publishes valid native volume")
 lakes._invalidate(AABB(Vector3.ZERO,Vector3.ONE*8));lakes._process(0)
 var token: int=terrain.request.token
 lakes.remove_lake(id);terrain.lake_slice_ready.emit(token,1,1,0)
 check(lakes.descriptions().is_empty() and lakes.statistics().outstanding_slices==0,"removal during bake discards late completion")
 lakes.free();terrain.free();await process_frame
 print("LAKE_EDITOR_LIFECYCLE failures=",failures);quit(1 if failures else 0)
