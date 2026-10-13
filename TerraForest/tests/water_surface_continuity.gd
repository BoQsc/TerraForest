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
func collect_surface(water) -> PackedVector3Array:
 var vertices:=PackedVector3Array()
 for step in 200:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  vertices.append_array(packet.arrays[Mesh.ARRAY_VERTEX])
 return vertices
func topology(vertices:PackedVector3Array) -> Dictionary:
 var edges:Dictionary={};var graph:Dictionary={};var valid:=not vertices.is_empty()
 for i in range(0,vertices.size(),3):
  valid=valid and (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length_squared()>1e-16
  for edge in 3:
   var a:String=str(vertices[i+edge].snapped(Vector3.ONE*0.00001));var b:String=str(vertices[i+(edge+1)%3].snapped(Vector3.ONE*0.00001))
   var key:=a+"|"+b if a<b else b+"|"+a
   edges[key]=edges.get(key,0)+1
   if not graph.has(a):graph[a]={}
   if not graph.has(b):graph[b]={}
   graph[a][b]=true;graph[b][a]=true
 for count in edges.values():valid=valid and count==2
 var seen:Dictionary={};var components:=0
 for vertex in graph:
  if seen.has(vertex):continue
  components+=1;var pending:Array=[vertex];seen[vertex]=true
  while not pending.is_empty():
   var current:String=pending.pop_back()
   for adjacent in graph[current]:
    if not seen.has(adjacent):seen[adjacent]=true;pending.append(adjacent)
 return {"closed":valid,"components":components}
func check_vertical(ledge:bool):
 var water=vertical_fixture(ledge)
 check(water!=null,"vertical-region fixture loads (ledge=%s)"%ledge)
 if water==null:return
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var before:PackedByteArray=water.capture_snapshot(catalog)
 var surface:=topology(collect_surface(water))
 check(surface.closed,"Cross-layer surface is closed and nondegenerate (ledge=%s)"%ledge)
 check(surface.components==(2 if ledge else 1),"Solid ledge separates pools; open layers connect (ledge=%s)"%ledge)
 check(water.capture_snapshot(catalog)==before,"cross-layer meshing preserves all authoritative state")
func check_vertical_repair():
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,424999)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);base+=16
 for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
 for y in range(3,7):
  var index:int=3+8*y+64*3
  bytes.encode_u16(base+index*12,0)
  bytes.encode_u64(base+index*12+4,([124999,125000,125000,50000][y-3])|(1<<63))
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(bytes),"Vertical repair fixture restores one-millilitre lower gap")
 check(not water.next_mesh().is_empty(),"Saved water can publish without advancing pending vertical repair")
 var conserved:=true
 water.advance(1)
 check(water.statistics().vertical_steps==1 and water.statistics().pending_vertical>0,"One operation repairs only one vertical face and queues the next")
 var saved:PackedByteArray=water.capture_snapshot(catalog)
 var restored=ClassDB.instantiate("NativeRegionalWater")
 check(restored.restore_snapshot(saved) and restored.statistics().pending_vertical>0,"Save and restore retain unfinished vertical work")
 for tick in 16:
  water.advance(1);restored.advance(1)
  conserved=conserved and water.statistics().water_ml==424999 and restored.statistics().water_ml==424999
 var result:PackedByteArray=water.capture_snapshot(catalog)
 var result_base:int=32+catalog.size()+16
 var correct:=true
 for y in range(3,7):
  var amount:int=result.decode_u64(result_base+(3+8*y+64*3)*12+4)&0x7fffffffffffffff
  correct=correct and amount==[125000,125000,125000,49999][y-3]
 check(correct and conserved and water.statistics().pending_vertical==0,"Vertical chain packs exactly without creating or losing a millilitre")
 check(not water.next_mesh().is_empty(),"Repaired column becomes eligible for mesh publication")
func pattern_fixture(mask:int,full:bool):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);base+=16
 for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
 var amount:=125000 if full else 1000;var total:=0
 for corner in 8:
  if (mask&(1<<corner))==0:continue
  var index:int=3+(corner&1)+8*(3+((corner>>1)&1))+64*(3+((corner>>2)&1))
  bytes.encode_u16(base+index*12,0);bytes.encode_u64(base+index*12+4,amount);total+=amount
 bytes.encode_u64(16,total)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func expected_components(mask:int,full:bool) -> int:
 var seen:=0;var count:=0
 for corner in 8:
  if (mask&(1<<corner))==0 or (seen&(1<<corner))!=0:continue
  count+=1;var pending:Array[int]=[corner];seen|=1<<corner
  while not pending.is_empty():
   var current:int=pending.pop_back()
   for axis in [1,2,4]:
    if axis==2 and not full:continue
    var next:int=current^axis
    if (mask&(1<<next))!=0 and (seen&(1<<next))==0:seen|=1<<next;pending.append(next)
 return count
func check_patterns():
 check(pattern_fixture(1,false).statistics().water_ml==1000 and pattern_fixture(255,false).statistics().water_ml==8000 and expected_components(5,false)==2 and expected_components(5,true)==1,"Pattern fixtures distinguish occupancy and vertical connectivity")
 var bad:Array=[]
 for full in [false,true]:
  for mask in range(1,256):
   var water=pattern_fixture(mask,full)
   var result:=topology(collect_surface(water))
   if not result.closed or result.components!=expected_components(mask,full):bad.append({"mask":mask,"full":full,"result":result})
 print("MATERIAL_PATTERN_FAILURES ",JSON.stringify(bad))
 check(bad.is_empty(),"All 510 shallow/full occupancy patterns are closed with correct component count")
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 check_vertical_repair()
 check_patterns()
 var water=fixture(false)
 check(water!=null,"two-region surface fixture loads")
 if water!=null:
  var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
  var before:PackedByteArray=water.capture_snapshot(catalog)
  var surface:=topology(collect_surface(water))
  check(surface.closed and surface.components==1,"Adjacent regions form one closed connected surface")
  check(water.capture_snapshot(catalog)==before,"mesh reconstruction preserves exact quantities and cached state")
 var invalidated=fixture(false)
 invalidated.invalidate(AABB(Vector3(45,41,41),Vector3.ONE*0.1))
 check(collect_surface(invalidated).is_empty(),"Invalid occupancy produces no newly exposed water geometry")
 check(invalidated.statistics().dirty_meshes>0 and invalidated.statistics().water_ml==150000,"Deferred work and water quantities survive terrain invalidation")
 var separate=fixture(true)
 var separated:=topology(collect_surface(separate))
 check(separated.closed and separated.components==2,"Diagonal water across solid neighbours remains two closed components")
 check_vertical(false)
 check_vertical(true)
 var halo=vertical_fixture(false)
 while not halo.next_mesh().is_empty():pass
 check(halo.brush(Vector3(43.75,43.9,41.75),0.0,1000)==1000,"local water edit accepted for mesh invalidation")
 var dirty:Array[Vector3i]=[]
 while true:
  var update:Dictionary=halo.next_mesh()
  if update.is_empty():break
  dirty.append(update.coordinate)
 check(dirty.has(Vector3i(10,11,10)),"Boundary edit invalidates the neighbouring upper region")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_surface_continuity.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_SURFACE_CONTINUITY failures=",failures);quit(failures)
