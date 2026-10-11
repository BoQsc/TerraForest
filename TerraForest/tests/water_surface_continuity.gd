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
func vertical_fixture(ledge:bool) -> RefCounted:
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var coordinates:Array[Vector3i]=[Vector3i(10,10,10),Vector3i(10,11,10),Vector3i(11,10,10)]
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+3*6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,3)
 bytes.encode_u64(16,250000 if ledge else 275000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 for r in 3:
  var base:int=32+catalog.size()+r*6160;var c:Vector3i=coordinates[r]
  bytes.encode_u64(base,(c.x<<24)|(c.y<<12)|c.z);bytes.encode_u32(base+8,1);base+=16
  for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
  var x:int=0 if r==2 else 7;var y:int=0 if r==1 else 7
  var i:=x+8*y+64*3
  bytes.encode_u16(base+i*12,200 if ledge and r==1 else 0)
  bytes.encode_u64(base+i*12+4,[125000,25000 if ledge else 50000,100000][r])
  if r==0:bytes.encode_u16(base+(7+8*4+64*3)*12,0)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func check_vertical(ledge:bool):
 var water=vertical_fixture(ledge)
 check(water!=null,"vertical-region fixture loads (ledge=%s)"%ledge)
 if water==null:return
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var before:PackedByteArray=water.capture_snapshot(catalog)
 var levels:Dictionary={};var side_count:=0;var edge_vertices:=0
 for region in 3:
  var mesh:Dictionary=water.next_mesh()
  if mesh.is_empty():continue
  side_count+=int(mesh.faces.side)
  var vertices:PackedVector3Array=mesh.arrays[Mesh.ARRAY_VERTEX]
  var normals:PackedVector3Array=mesh.arrays[Mesh.ARRAY_NORMAL]
  for i in vertices.size():
   if abs(vertices[i].x-44.0)<0.00001 and normals[i].y>0.5:
    levels[roundi(vertices[i].y*1000)]=true;edge_vertices+=1
 if ledge:check(levels.has(43950) and levels.has(44300) and levels.size()==2,"solid ledge keeps upper pool distinct from joined lower water")
 else:check(levels.size()==1 and levels.has(44050) and edge_vertices==6 and side_count==0,"height-layer crossing shares surface without a submerged wall")
 check(water.capture_snapshot(catalog)==before,"cross-layer meshing preserves all authoritative state")
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
 check_vertical(false)
 check_vertical(true)
 var halo=vertical_fixture(false)
 while not halo.next_mesh().is_empty():pass
 check(halo.brush(Vector3(43.75,42.1,41.75),0.0,1000)==1000,"local water edit accepted for mesh invalidation")
 var dirty:Array[Vector3i]=[]
 while true:
  var update:Dictionary=halo.next_mesh()
  if update.is_empty():break
  dirty.append(update.coordinate)
 check(dirty.has(Vector3i(10,11,10)),"mesh invalidation includes upper region reached by full-cell surface dependency")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_surface_continuity.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_SURFACE_CONTINUITY failures=",failures);quit(failures)
