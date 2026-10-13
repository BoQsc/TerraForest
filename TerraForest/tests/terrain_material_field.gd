# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(core.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))),"TerrainCore accepts an empty material field")
 if failures:finish();return
 var initial:PackedByteArray=core.execute(Codec.command(0))
 check(initial.decode_u32(20)==0,"Empty material field allocates no density pages")
 var generator:PackedByteArray=core.execute(Codec.command(25))
 check(generator.decode_u32(12)==Codec.MATERIAL_FIELD_GENERATOR and generator.decode_u32(20)==0,"Empty material field has no generated cave primitives")
 for point:Vector3 in [Vector3(16,8,16),Vector3(1000,100,1000),Vector3(1999,1,1999)]:
  var sampled:PackedByteArray=core.execute(Codec.point_command(point))
  check(sampled.decode_float(12)==0 and sampled.decode_float(16)>0,"Material base is empty throughout the world: "+str(point))
 var empty:PackedByteArray=core.execute(Codec.command(1,[16,16,16,1]))
 check(Codec.reply_ok(empty) and empty.decode_u32(40)==0,"Ordinary terrain mesher produces no phantom land")
 var center:=Vector3(24,12,24)
 var edit:PackedByteArray=core.execute(Codec.brush(center,center,2,1,true,0))
 check(Codec.reply_ok(edit) and edit.decode_u32(16)>0,"Normal terrain box command places material directly in the field")
 check(core.execute(Codec.point_command(center)).decode_float(16)<0,"Placed material is the authoritative density, not a rendered proxy")
 var placed:PackedByteArray=core.execute(Codec.command(1,[16,16,16,1]))
 check(placed.decode_u32(40)>0 and placed.decode_u32(44)>0,"Normal terrain mesher produces the placed material surface")
 var cached:PackedByteArray=core.execute(Codec.command(20,[16,16,16,1]))
 check(cached.slice(12)==placed.slice(12),"Existing terrain geometry cache produces byte-identical material geometry")
 var before:PackedByteArray=core.execute(Codec.command(21))
 core.execute(Codec.command(20,[16,16,16,1]))
 var after:PackedByteArray=core.execute(Codec.command(21))
 check(after.decode_u64(12)>before.decode_u64(12) and after.decode_u64(20)==before.decode_u64(20),"Warm material mesh uses cache hits without additional misses")
 var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 var restored=ClassDB.instantiate("TerrainCore");var load_packet:=Codec.command(5);load_packet.append_array(saved)
 check(Codec.reply_ok(restored.execute(load_packet)),"Existing terrain archive reloads the material field")
 check(restored.execute(Codec.command(4)).slice(12)==saved,"Material density save roundtrip is byte-exact")
 check(restored.execute(Codec.command(1,[16,16,16,1]))==placed,"Reloaded material geometry is byte-exact")
 core.execute(Codec.brush(center,center,3,1,false,0))
 var removed:PackedByteArray=core.execute(Codec.command(20,[16,16,16,1]))
 check(removed.decode_u32(40)==0 and core.execute(Codec.point_command(center)).decode_float(16)>0,"Normal terrain removal retires the cached material surface")
 check(restored.execute(Codec.point_command(center)).decode_float(16)<0,"Independent material-field owners do not mutate each other")
 var solid=ClassDB.instantiate("TerrainCore")
 solid.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
 solid.execute(Codec.brush(Vector3(24,10,24),Vector3(24,10,24),3,1,true,0))
 var solid_revision:int=solid.execute(Codec.command(0)).decode_u32(12)
 var material=ClassDB.instantiate("TerrainCore")
 material.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
 var receipt:Dictionary=material.material_box(solid,Vector3(20,8,20),Vector3(28,16,28),true,solid_revision)
 check(receipt.get("accepted",false) and receipt.get("changes",0)>0,"Terrain-aware placement commits direct density changes")
 check(material.execute(Codec.point_command(Vector3(24,10,24))).decode_float(16)>0,"Material excludes authoritative solid terrain")
 check(material.execute(Codec.point_command(Vector3(24,15,24))).decode_float(16)<0,"Material occupies air above solid terrain")
 var exclusion_ok:=true
 for y in range(7,18):
  for z in range(19,30):
   for x in range(19,30):
    var point:=Vector3(x,y,z)
    if solid.execute(Codec.point_command(point)).decode_float(16)<=0 and material.execute(Codec.point_command(point)).decode_float(16)<0:exclusion_ok=false
 check(exclusion_ok,"No edited sample is simultaneously solid terrain and material")
 var field_save:PackedByteArray=material.execute(Codec.command(4)).slice(12)
 var stale:Dictionary=material.material_box(solid,Vector3(20,8,20),Vector3(28,16,28),false,solid_revision-1)
 check(not stale.get("accepted",false) and material.execute(Codec.command(4)).slice(12)==field_save,"Stale terrain revision rejects without mutation")
 var invalid:Dictionary=material.material_box(solid,Vector3(28,8,20),Vector3(20,16,28),false,solid_revision)
 check(not invalid.get("accepted",false) and material.execute(Codec.command(4)).slice(12)==field_save,"Invalid brush rejects without mutation")
 var direct_mesh:PackedByteArray=material.execute(Codec.command(20,[16,16,16,1]))
 check(direct_mesh.decode_u32(40)>0,"Terrain-aware field uses cached terrain meshing")
 var load_field:=Codec.command(5);load_field.append_array(field_save)
 restored.execute(load_field)
 check(restored.execute(Codec.command(20,[16,16,16,1]))==direct_mesh,"Terrain-aware field reloads identical geometry")
 var removed_receipt:Dictionary=material.material_box(solid,Vector3(19,7,19),Vector3(29,17,29),false,solid_revision)
 check(removed_receipt.get("accepted",false) and material.execute(Codec.command(20,[16,16,16,1])).decode_u32(40)==0,"Direct removal clears cached surface")
 finish()
func finish():
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/terrain_material_field.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual TerrainCore edit, extraction, cache and archive paths on an empty field. Not lake integration, flow or bucket conservation."},"  "));file.close()
 print("TERRAIN_MATERIAL_FIELD failures=",failures);quit(failures)
