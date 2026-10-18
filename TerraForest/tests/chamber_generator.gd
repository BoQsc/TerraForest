# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func density(core:RefCounted,p:Vector3)->float:
 var query:=Codec.point_command(p);query.encode_u32(0,26)
 return core.execute(query).decode_float(16)
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(core.execute(Codec.command(6,[1703,8]))),"chamber generator accepted")
 var desc:PackedByteArray=core.execute(Codec.command(25))
 check(desc.decode_u32(20)==28,"four networks with three chambers and four connecting passages each")
 for network in 4:
  var at:=24+(network*7+2)*28
  var center:=Vector3(desc.decode_float(at),desc.decode_float(at+4),desc.decode_float(at+8))
  var radius:=desc.decode_float(at+24)
  var floor_ok:=true
  for x in range(-20,21,4):
   for z in range(-20,21,4):
    var p:=center+Vector3(x,0,z)
    floor_ok=floor_ok and density(core,p+Vector3.UP*2)>0 and density(core,p-Vector3.UP*2)<0
  check(floor_ok,"wide supported floor in chamber %d"%network)
  check(radius>=32 and density(core,center+Vector3.UP*(radius-2))>0 and density(core,center+Vector3.UP*(radius+2))<0,"domed ceiling has more than thirty metres of headroom")
 var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 core.execute(Codec.command(6,[1704,8]))
 check(core.execute(Codec.command(25))!=desc,"seed changes chamber locations")
 var restore:=Codec.command(5);restore.append_array(saved)
 check(Codec.reply_ok(core.execute(restore)) and core.execute(Codec.command(25))==desc,"saved generator restores exact chamber geometry")
 check(not preload("res://addons/volumetric_terrain/generated_layout.gd").describe(1703,8).is_empty(),"chamber world retains regional layout metadata")
 print("CHAMBER_GENERATOR failures=",failures);quit(1 if failures else 0)
