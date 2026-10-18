# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
 var scatter=ClassDB.instantiate("NativeGroundCover")
 var state=ClassDB.instantiate("NativeGroundCoverState");state.bind_world(1703,1)
 var anchors:=PackedVector3Array([Vector3(974,0,974),Vector3(980,0,980)])
 var changed:=0;var total:=0;var seen:Dictionary={};var valid:=true
 var bins:Dictionary={}
 for layer in 16:
  var plain:Dictionary=scatter.candidates(Vector2i(30,30),1703,layer)
  var clustered:Dictionary=scatter.candidates(Vector2i(30,30),1703,layer,anchors)
  valid=valid and clustered==scatter.candidates(Vector2i(30,30),1703,layer,anchors) and clustered.ids==plain.ids and clustered.ids.size()==64
  for i in clustered.ids.size():
   var point:Vector3=clustered.points[i]
   valid=valid and point.x>=960 and point.x<992 and point.z>=960 and point.z<992 and not seen.has(clustered.ids[i])
   seen[clustered.ids[i]]=true;total+=1
   if layer==0:valid=valid and point==plain.points[i]
   elif point!=plain.points[i]:changed+=1
   var key:=Vector2i(floori(point.x),floori(point.z));bins[key]=bins.get(key,0)+1
  var normals:=PackedVector3Array();normals.resize(64);normals.fill(Vector3.UP)
  var placed:Dictionary=scatter.place(clustered.ids,clustered.points,normals)
  state.mark(clustered.ids[0])
  var rows:Array=scatter.pack(placed.ids,placed.transforms,state.mask(placed.ids),anchors)
  var count:=0
  for row in rows:
   count+=row.ids.size();valid=valid and not row.ids.has(clustered.ids[0])
  valid=valid and count==63
 check(valid and total==1024,"fixed candidate budget, deterministic owners and per-ID removals")
 check(changed>0,"tree recipe influences detail placement while base stones remain fixed")
 var multiple:=0
 for count in bins.values():
  if count>=3:multiple+=1
 check(multiple>10 and bins.size()<850,"irregular occupied pockets and open one-metre cells")
 var saved:PackedByteArray=state.capture_storage_snapshot();var fresh=ClassDB.instantiate("NativeGroundCoverState")
 check(fresh.restore_storage_snapshot(saved) and fresh.capture_storage_snapshot()==saved,"harvest IDs persist independently of placement recipe")
 var huge:=PackedVector3Array();huge.resize(145)
 check(scatter.candidates(Vector2i(30,30),1703,1,huge).ids.is_empty(),"anchor work capped at 144")
 print("DISTRIBUTION bins=",bins.size()," multi=",multiple," sheltered_moves=",changed," failures=",failures);quit(1 if failures else 0)
