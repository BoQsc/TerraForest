# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+9076);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,10000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1)
 for i in 512:bytes.encode_u16(base+16+i*12,500);bytes.encode_u16(base+18+i*12,500)
 var index:=3+8*3+64*3;bytes.encode_u16(base+16+index*12,250);bytes.encode_u64(base+20+index*12,10000)
 for i in 729:
  var x:float=40+(i%9)*0.5;var y:float=40+((i/9)%9)*0.5
  bytes.encode_float(base+6160+i*4,y-(41.5+(x-41.5)*0.5))
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(bytes),"Old cached terrain restores without resampling")
 var geometry:Dictionary=water.cell_geometry(Vector3(41.75,41.75,41.75))
 check(geometry.cut and geometry.capacity_ml==93750 and abs(geometry.head-(41.5+sqrt(20000.0)*0.001))<0.00001,"Runtime cut-cell level follows wedge volume instead of highest corner")
 check(water.statistics().active_cells>0 and water.statistics().pending_regions==0,"Version 2 upgrade wakes changed cut capacity using cached terrain")
 # Version 3 also needs to wake the newly supported partially open top cell.
 var previous:=bytes.duplicate();previous.encode_u32(4,3)
 for i in 729:
  var x:float=40+(i%9)*0.5;var y:float=40+((i/9)%9)*0.5
  previous.encode_float(base+6160+i*4,y-(41.9+(x-41.5)*0.4))
 previous.encode_u16(base+16+index*12,500)
 var migrated=ClassDB.instantiate("NativeRegionalWater")
 check(migrated.restore_snapshot(previous),"Version 3 partial-top archive restores")
 var partial:Dictionary=migrated.cell_geometry(Vector3(41.75,41.75,41.75))
 check(partial.cut and abs(partial.capacity_ml-6250)<=2 and migrated.statistics().active_cells>0 and migrated.statistics().pending_regions==0 and migrated.statistics().water_ml==10000,"Version 3 partial-top migration wakes cached water without losing volume")
 var upgraded:PackedByteArray=water.capture_snapshot(catalog)
 check(upgraded.decode_u32(4)==4 and water.statistics().water_ml==10000,"Version 4 upgrade preserves every millilitre")
 var reopened=ClassDB.instantiate("NativeRegionalWater")
 check(reopened.restore_snapshot(upgraded) and reopened.capture_snapshot(catalog)==upgraded,"Cut-cell archive roundtrip preserves cached data and pending work")
 check(water.depth_at(Vector3(41.55,41.55,41.75))>0.09 and water.depth_at(Vector3(41.9,41.55,41.75))==0,"Depth query distinguishes wet and dry parts inside one cut cell")
 var edges:Dictionary={};var vertices:=0
 for packet_index in 40:
  var packet:Dictionary=water.next_mesh(true)
  if packet.is_empty():break
  var points:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX];vertices+=points.size()
  for i in range(0,points.size(),3):
   for e in 3:
    var a:Vector3i=Vector3i((points[i+e]*100000).round());var b:Vector3i=Vector3i((points[i+(e+1)%3]*100000).round())
    var sa:=str(a);var sb:=str(b);var key:String=(sa+"/"+sb) if sa<sb else (sb+"/"+sa)
    edges[key]=edges.get(key,0)+1
 var closed:bool=vertices>0
 for count:int in edges.values():closed=closed and count==2
 check(closed,"Cut-cell stored-volume envelope is closed with two incident triangles per edge")
 var point:Vector3=geometry.wet_centroid;var hit:Dictionary=water.raycast_surface(point+Vector3.UP,point-Vector3.UP)
 check(hit.hit and hit.point.y>point.y and hit.point.y<=geometry.head+0.00001,"Bucket query hits the same finite cut-cell surface")
 check(water.capture_snapshot(catalog)==upgraded,"Meshing and picking never alter cut-cell quantities")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_cut_cells.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"vertices":vertices,"capacity_ml":geometry.capacity_ml,"head":geometry.head}));report.close()
 print("WATER_CUT_CELLS failures=",failures);quit(failures)
