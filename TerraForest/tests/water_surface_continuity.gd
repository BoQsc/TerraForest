# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(diagonal:bool) -> RefCounted:
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var count:=1 if diagonal else 2
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+count*6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,count);bytes.encode_u64(16,150000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 for r in count:
  var base:int=32+catalog.size()+r*6160
  bytes.encode_u64(base,((10+r)<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);base+=16
  for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
  var x:=3 if diagonal else (7 if r==0 else 0)
  var i:=x+8*3+64*3
  bytes.encode_u16(base+i*12,0);bytes.encode_u64(base+i*12+4,100000 if r==0 else 50000)
  if diagonal:
   i=4+8*3+64*4;bytes.encode_u16(base+i*12,0);bytes.encode_u64(base+i*12+4,50000)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var water=fixture(false)
 check(water!=null,"two-region surface fixture loads")
 if water!=null:
  var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
  var before:PackedByteArray=water.capture_snapshot(catalog)
  var edge_count:=0;var valid:=true;var triangles:=0
  for r in 2:
   var mesh:Dictionary=water.next_mesh();var v:PackedVector3Array=mesh.arrays[Mesh.ARRAY_VERTEX];var n:PackedVector3Array=mesh.arrays[Mesh.ARRAY_NORMAL]
   triangles+=v.size()/3
   for i in v.size():
    valid=valid and n[i].y>0.5
    if abs(v[i].x-44.0)<0.00001:
     edge_count+=1;valid=valid and abs(v[i].y-41.8)<0.00001
  check(valid and edge_count==6 and triangles==4,"adjacent regions share identical surface edge without internal wall")
  check(water.capture_snapshot(catalog)==before,"mesh reconstruction preserves exact quantities and cached state")
 var separate=fixture(true)
 var mesh:Dictionary=separate.next_mesh();var v:PackedVector3Array=mesh.arrays[Mesh.ARRAY_VERTEX]
 var levels:Dictionary={}
 for p in v:
  if abs(p.x-42.0)<0.00001 and abs(p.z-42.0)<0.00001:levels[roundi(p.y*1000)]=true
 check(levels.has(41900) and levels.has(41700) and levels.size()==2,"diagonal contact through solid neighbours does not join water surfaces")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_surface_continuity.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_SURFACE_CONTINUITY failures=",failures);quit(failures)
