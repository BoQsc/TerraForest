# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize() -> void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var codec: RefCounted=ClassDB.instantiate("NativeRoadEditorSettings")
 var data: PackedByteArray=codec.encode(1,5.5,7,11,3.5)
 check(data.size()==48 and codec.validate_snapshot(data),"bounded settings roundtrip")
 var decoded: Dictionary=codec.decode(data)
 check(decoded.ok and decoded.surface==1 and decoded.width==5.5 and decoded.depth==7 and decoded.clearance==11 and decoded.shoulder==3.5,"exact settings decode")
 check(codec.decode(PackedByteArray()).width==3,"legacy empty default")
 for offset in [0,4,8,12]:
  var bad:=data.duplicate();bad.encode_u32(offset,99)
  check(not codec.validate_snapshot(bad),"invalid header %d"%offset)
 for offset in [16,24,32,40]:
  for value in [NAN,INF,-1.0,100.0]:
   var bad:=data.duplicate();bad.encode_double(offset,value)
   check(not codec.validate_snapshot(bad),"invalid numeric %d %s"%[offset,str(value)])
 var trailing:=data.duplicate();trailing.append(0)
 check(not codec.validate_snapshot(trailing) and not codec.validate_snapshot(data.slice(0,47)),"exact length enforced")
 check(codec.encode(0,0.5,1,0,0).size()==48 and codec.encode(1,16,8,16,16).size()==48,"inclusive bounds")
 check(codec.encode(2,3,2,0,0).is_empty() and codec.encode(0,NAN,2,0,0).is_empty(),"invalid encoding rejected")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/road_editor_settings.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 quit(1 if failures else 0)
