# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(x:int,floor_mm:int):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,1000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);base+=16
 for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
 var i:=x+8*3+64*3;bytes.encode_u16(base+i*12,floor_mm);bytes.encode_u64(base+i*12+4,1000)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func check_batch():
 var reference=fixture(7,0);var expected:Dictionary={}
 for step in 100:
  var packet:Dictionary=reference.next_mesh()
  if packet.is_empty():break
  expected[packet.coordinate]=packet.arrays
 var water=fixture(7,0);var collected:Dictionary={};var changed:=false;var complete:=false;var stable:=true;var completed_id:=0
 var origin:=Vector3(43.75,41.501,41.75)
 for step in 100:
  var packet:Dictionary=water.next_mesh_batch()
  if packet.is_empty():break
  if packet.has("coordinate"):collected[packet.coordinate]=packet.arrays
  if not changed:
   changed=water.brush(origin,0.0,1000)==1000
   stable=stable and water.statistics().mesh_snapshot_bytes>0
  if packet.complete:complete=true;completed_id=packet.batch;break
 stable=stable and expected.size()==collected.size()
 for coordinate in expected:
  stable=stable and collected.has(coordinate)
  if collected.has(coordinate):stable=stable and collected[coordinate]==expected[coordinate]
 check(complete and changed and stable,"Publication batch keeps one immutable surface while live water changes")
 check(water.statistics().water_ml==2000 and water.statistics().dirty_meshes>0 and water.statistics().mesh_snapshot_bytes==0,"Live edit survives batch and snapshots retire at completion")
 check(not water.raycast_surface(origin+Vector3.UP,origin-Vector3.UP).hit,"Unpublished staged geometry is not pickable")
 check(not water.commit_mesh_batch(completed_id+1) and water.commit_mesh_batch(completed_id),"Only the completed render batch can publish query geometry")
 var reference_hit:Dictionary=reference.raycast_surface(origin+Vector3.UP,origin-Vector3.UP)
 var published_hit:Dictionary=water.raycast_surface(origin+Vector3.UP,origin-Vector3.UP)
 check(published_hit.hit and published_hit.point==reference_hit.point,"Published query matches displayed snapshot rather than newer live amounts")
 var stayed:=true;var next_id:=0
 for step in 100:
  var packet:Dictionary=water.next_mesh_batch()
  if step==0:water.brush(origin,0.0,1000)
  var hit:Dictionary=water.raycast_surface(origin+Vector3.UP,origin-Vector3.UP)
  stayed=stayed and hit.hit and hit.point==published_hit.point
  if packet.complete:next_id=packet.batch;break
 check(stayed and water.commit_mesh_batch(next_id),"Targeting retains old displayed triangles throughout the next staged batch")
 var updated:Dictionary=water.raycast_surface(origin+Vector3.UP,origin-Vector3.UP)
 check(updated.hit and updated.point.y>published_hit.point.y and water.statistics().query_builds==0,"Query surface advances at publication without rebuilding geometry")
 var next:Dictionary=water.next_mesh_batch();var old_batch:int=next.batch
 water.invalidate(AABB(origin-Vector3.ONE*0.01,Vector3.ONE*0.02))
 var restarted:Dictionary=water.next_mesh_batch()
 check(not restarted.is_empty() and restarted.batch>old_batch and not water.commit_mesh_batch(old_batch),"Terrain invalidation cancels staged publication and changes batch identity")
 var saved:PackedByteArray=fixture(7,0).capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
 check(water.restore_snapshot(saved) and water.statistics().query_cache_bytes==0 and not water.raycast_surface(origin+Vector3.UP,origin-Vector3.UP).hit,"Restore retires old published geometry until replacement is displayed")
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 check_batch()
 var closed:=true;var visible:=true;var bounded:=true;var conserved:=true;var shared:=true;var cases:=0;var picked:=true;var missed:=true;var nearest_matches:=true;var invalid_misses:=true
 for x in [0,7]:
  for floor_mm in range(0,491,35):
   var water=fixture(x,floor_mm)
   if water==null:quit(2);return
   var before:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
   var edges:Dictionary={};var count:=0;var low:=INF;var high:=-INF
   for step in 100:
    var packet:Dictionary=water.next_mesh()
    if packet.is_empty():break
    shared=shared and packet.faces.get("shared_surface_nets",false)
    var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
    for v in vertices:
     low=minf(low,v.y);high=maxf(high,v.y)
     bounded=bounded and v.y>=41.5+floor_mm*0.001-0.00002 and v.y<=41.5+floor_mm*0.001+0.00402
    for t in range(0,vertices.size(),3):
     count+=1
     for e in 3:
      var a:String=str(vertices[t+e].snapped(Vector3.ONE*0.00001));var b:String=str(vertices[t+(e+1)%3].snapped(Vector3.ONE*0.00001))
      var key:=a+"|"+b if a<b else b+"|"+a
      edges[key]=edges.get(key,0)+1
   for value in edges.values():closed=closed and value==2
   visible=visible and count>0 and high-low>0.001
   conserved=conserved and before==water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
   var center:=Vector3(40.25+x*0.5,41.5+floor_mm*0.001,41.75)
   var hit:Dictionary=water.raycast_surface(center+Vector3.UP,center-Vector3.UP)
   picked=picked and hit.get("hit",false) and hit.get("cell",Vector3i.ZERO)==Vector3i(80+x,83,83)
   if hit.get("hit",false):picked=picked and absf(hit.point.y-high)<0.00002
   var outside:=center+Vector3(0.4,0,0)
   missed=missed and not water.raycast_surface(outside+Vector3.UP,outside-Vector3.UP).hit
   conserved=conserved and before==water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
   var nearest:Vector3=water.surface_near(center+Vector3.UP*0.1,0.2)
   nearest_matches=nearest_matches and nearest.is_finite() and absf(nearest.y-high)<0.00002
   water.invalidate(AABB(center-Vector3.ONE*0.01,Vector3.ONE*0.02))
   invalid_misses=invalid_misses and not water.raycast_surface(center+Vector3.UP,center-Vector3.UP).hit
   cases+=1
 check(shared,"Water packets use shared surface-nets reconstruction")
 check(visible,"One-litre puddles retain nonzero geometry across vertical offsets")
 check(bounded,"Thin-water vertices stay between actual bottom and top")
 check(closed,"Region-boundary puddles have exactly two triangles per welded edge")
 check(nearest_matches,"Nearest-surface query agrees with reconstructed upper surface")
 check(invalid_misses,"Unknown terrain occupancy is not pickable")
 check(picked,"Thin-water ray hits rendered top and correct owning volume cell")
 check(missed,"Rays outside rendered puddle miss")
 check(conserved,"Meshing leaves stored quantity and snapshot unchanged")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_material_surface.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"cases":cases}));file.close()
 print("WATER_MATERIAL_SURFACE cases=",cases," failures=",failures)
 quit(0 if failures==0 else 1)
