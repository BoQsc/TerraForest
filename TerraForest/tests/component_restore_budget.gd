# SPDX-License-Identifier: 0BSD
extends SceneTree
class Host extends Node:
 var snapshot_restore_ok:=true
 var prepared_snapshot_components:Dictionary={}
class Provider extends RefCounted:
 var calls:=0
 var succeeds:=true
 func restore(_bytes:PackedByteArray)->bool:
  calls+=1;OS.delay_usec(100);return succeeds
 func capture()->PackedByteArray:return PackedByteArray([calls])
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 var host:=Host.new();persistence._terrain=host
 var a:=Provider.new();var b:=Provider.new();b.succeeds=false
 persistence._providers={"a":{"restore":a.restore,"capture":a.capture,"empty":PackedByteArray()},"b":{"restore":b.restore,"capture":b.capture,"empty":PackedByteArray()}}
 persistence._begin_restore({},7)
 check(not persistence._advance_restore(1) and a.calls==1 and b.calls==0,"budget yields between ordered providers")
 check(persistence._capture().epoch==-1 and persistence._capture().sections.is_empty(),"partial restoration cannot capture a save")
 check(persistence._advance_restore(1) and b.calls==1 and not host.snapshot_restore_ok,"failed provider completes barrier with explicit failure")
 check(persistence._restored_epoch==7 and not persistence._restoring,"restored epoch advances only at completion")
 check(persistence._capture().epoch==-1,"failed restoration cannot capture a save")
 check(persistence._advance_restore(1) and a.calls==1 and b.calls==1,"completed step never restores twice")
 host.snapshot_restore_ok=true;b.succeeds=true;persistence._restore({},8)
 check(persistence._restored_epoch==8 and a.calls==2 and b.calls==2 and host.snapshot_restore_ok,"synchronous compatibility path restores all providers")
 var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
 var begin:=func(_sections:Dictionary,_epoch:int)->void:pass
 var step:=func(_budget:int)->bool:return false
 terrain.configure_snapshot_restore(begin,step)
 terrain._receive({"kind":"startup","message":"loaded","components":{}})
 check(not terrain.world_ready and not terrain._restore_pending.is_empty(),"facade holds world publication until restoration completes")
 var epoch:int=terrain.epoch;terrain.reload_world()
 check(terrain.epoch==epoch,"second reload cannot interrupt partial restoration")
 terrain.shutdown()
 check(not terrain.backend._snapshot_writable() and terrain.backend._shutdown_snapshot.is_empty() and terrain._restore_pending.is_empty(),"shutdown during restoration blocks partial snapshot publication")
 terrain.free()
 host.free();print("COMPONENT_RESTORE_BUDGET failures=",failures);quit(1 if failures else 0)
