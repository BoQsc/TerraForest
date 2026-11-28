# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var scatter=ClassDB.instantiate("NativeVegetationScatter")
 var legacy:Dictionary=scatter.candidates(Vector2i(10,20),42,0.82)
 var empty:PackedByteArray=scatter.capture_storage_snapshot()
 var failures:=0
 if not scatter.configure_groves(PackedVector3Array([Vector3(1024,32,256)])):failures+=1
 var added:Dictionary=scatter.candidates(Vector2i(16,4),42,0.82)
 if added.ids.is_empty():failures+=1
 if scatter.candidates(Vector2i(10,20),42,0.82)!=legacy:failures+=1
 var saved:PackedByteArray=scatter.capture_storage_snapshot()
 var restored=ClassDB.instantiate("NativeVegetationScatter")
 if not restored.restore_storage_snapshot(saved) or restored.candidates(Vector2i(16,4),42,0.82)!=added:failures+=1
 for bad in [saved.slice(0,saved.size()-1),PackedByteArray([0]),PackedByteArray()]:
  if restored.validate_snapshot(bad) or restored.restore_storage_snapshot(bad) or restored.capture_storage_snapshot()!=saved:failures+=1
 if scatter.configure_groves(PackedVector3Array([Vector3(1024,INF,256)])) or scatter.capture_storage_snapshot()!=saved:failures+=1
 if scatter.configure_groves(PackedVector3Array([Vector3(1024,65,256)])):failures+=1
 var huge:=PackedVector3Array();huge.resize(33);huge.fill(Vector3(1024,16,256))
 if scatter.configure_groves(huge):failures+=1
 if not scatter.restore_storage_snapshot(empty) or not scatter.candidates(Vector2i(16,4),42,0.82).ids.is_empty():failures+=1
 var core=ClassDB.instantiate("TerrainCore")
 var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
 core.execute(codec.command(6,[1703,38]))
 var program:PackedByteArray=core.shore_habitat_program()
 if program.size()<40 or program.size()>9232 or not scatter.configure_shores(program):failures+=1
 var shore_saved:PackedByteArray=scatter.capture_storage_snapshot()
 if shore_saved.decode_u32(0)!=0x32565247 or not restored.restore_storage_snapshot(shore_saved) or restored.capture_storage_snapshot()!=shore_saved:failures+=1
 var control=ClassDB.instantiate("NativeVegetationScatter")
 var changed:=0;var same:=0;var stable:=true;var total:=0;var previous_total:=0
 var started:=Time.get_ticks_usec()
 for z in 32:
  for x in 32:
   var cell:=Vector2i(x,z)
   var before:Dictionary=control.candidates(cell,1703,.82,true,1)
   var after:Dictionary=scatter.candidates(cell,1703,.82,true,1)
   total+=after.ids.size();previous_total+=before.ids.size()
   if after!=restored.candidates(cell,1703,.82,true,1):failures+=1
   if before==after:same+=1
   else:changed+=1
   # Shared candidates retain identity, position, rotation and scale. Only the
   # admission weight changes; density is never implemented with extra trials.
   for i in after.ids.size():
    var j:int=before.ids.find(after.ids[i])
    if j>=0:stable=stable and after.points[i]==before.points[j] and after.rotations[i]==before.rotations[j] and after.scales[i]==before.scales[j]
 if changed==0 or same<500 or not stable:failures+=1
 var elapsed:=Time.get_ticks_usec()-started
 for offset in [0,4,8,12,16,24]:
  var bad:=program.duplicate();bad.encode_u32(offset,0xffffffff)
  if scatter.configure_shores(bad) or scatter.capture_storage_snapshot()!=shore_saved:failures+=1
 for bad in [shore_saved.slice(0,shore_saved.size()-1),shore_saved+PackedByteArray([0])]:
  if restored.restore_storage_snapshot(bad) or restored.capture_storage_snapshot()!=shore_saved:failures+=1
 if not restored.restore_storage_snapshot(empty) or restored.capture_storage_snapshot()!=empty or restored.candidates(Vector2i(26,21),1703,.82,true,1)!=control.candidates(Vector2i(26,21),1703,.82,true,1):failures+=1
 core.execute(codec.command(6,[1703,37]))
 if not core.shore_habitat_program().is_empty():failures+=1
 print("SHORE_HABITAT bytes=",program.size()," changed_cells=",changed," identical_cells=",same," before_candidates=",previous_total," candidates=",total," three_world_scatter_passes_us=",elapsed," stable_ids=",stable)
 print("VEGETATION_GROVES failures=",failures," added_candidates=",added.ids.size())
 quit(1 if failures else 0)
