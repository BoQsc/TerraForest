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
 var trailer_size:=4+512*4+4*36
 var data:=PackedByteArray();data.resize(32+catalog.size()+9076+trailer_size);data.fill(0)
 data.encode_u32(0,0x31575256);data.encode_u32(4,6);data.encode_u32(8,catalog.size());data.encode_u32(12,1);data.encode_u64(16,41667);data.encode_u64(24,trailer_size)
 for i in catalog.size():data[32+i]=catalog[i]
 var base:int=32+catalog.size();data.encode_u64(base,(10<<24)|(10<<12)|10);data.encode_u32(base+8,1);data.encode_u32(base+12,1)
 for i in 512:data.encode_u16(base+18+i*12,500)
 for i in 729:data.encode_float(base+6160+i*4,1.0)
 var cell:=3+8*3+64*3;data.encode_u64(base+20+cell*12,41667)
 var at:=base+9076;data.encode_u32(at,1);at+=4
 var count_at:=0
 var corners:=[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0)]
 for i in 512:
  data.encode_u32(at,4 if i==cell else 0)
  if i==cell:count_at=at
  at+=4
  if i!=cell:continue
  for j in 4:
   for point:Vector3 in [corners[j],corners[(j+1)%4],Vector3(0.5,0.5,250)]:
    data.encode_float(at,point.x);data.encode_float(at+4,point.y);data.encode_float(at+8,point.z);at+=12
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(data),"Terrain contact triangle cache restores")
 var shape:Dictionary=water.cell_geometry(Vector3(41.75,41.75,41.75))
 # Pyramid volume: base 0.25 m² * height 0.25 m / 3 = 20.8333 L.
 # Air below height 0.25 m: 62.5 - 20.8333 = 41.6667 L.
 check(shape.capacity_ml==104166 and absf(shape.head-41.7500013333)<0.00001,"Analytic pyramid volume sets the correct water height rather than interpolating four flat corners")
 check(absf(shape.bottom-41.75)<0.000001 and absf(water.cell_geometry(Vector3(41.5,41.75,41.5)).bottom-41.5)<0.000001,"Contact retains the interior terrain peak and corner heights")
 var canonical:PackedByteArray=water.capture_snapshot(catalog)
 var reopened=ClassDB.instantiate("NativeRegionalWater")
 check(reopened.restore_snapshot(canonical) and reopened.capture_snapshot(catalog)==canonical and reopened.cell_geometry(Vector3(41.75,41.75,41.75))==shape,"Migrated contact triangles and exact quantity roundtrip canonically")
 var malformed:=data.duplicate();malformed.encode_u32(count_at,129)
 check(not water.restore_snapshot(malformed) and water.statistics().water_ml==41667,"Oversized contact list is rejected atomically")
 malformed=data.duplicate();malformed.encode_float(count_at+4,NAN)
 check(not water.restore_snapshot(malformed) and water.statistics().water_ml==41667,"Non-finite cached triangle is rejected atomically")
 var sliver:=data.duplicate()
 for triangle in 4:
  for vertex in 3:
   var offset:int=count_at+4+triangle*36+vertex*12
   sliver.encode_float(offset+8,0.0)
   if vertex==2:sliver.encode_float(offset,1e-10)
 check(water.restore_snapshot(sliver),"Small-area terrain triangles are valid contact geometry")
 var sliver_vertices:=0
 var sliver_degenerate:=0
 for step in 100:
  var packet:Dictionary=water.next_mesh(true)
  if packet.is_empty():break
  sliver_vertices+=packet.vertices
  var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,vertices.size(),3):
   if (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length_squared()==0:sliver_degenerate+=1
 check(sliver_vertices>0 and not water.statistics().surface_budget_failed and water.statistics().water_ml==41667,"Clipping plane validity is independent of terrain triangle area")
 check(sliver_degenerate==0,"Sub-precision contact fragments do not emit degenerate render triangles")
 var shallow:=data.duplicate();shallow.encode_u64(16,29167);shallow.encode_u64(base+20+cell*12,29167)
 check(water.restore_snapshot(shallow),"Partial fill exposes the terrain peak above water")
 var top_samples:=0;var above_floor:=true;var minimum_clearance:=INF;var free_top_samples:=0;var unresolved:=0
 for step in 100:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  unresolved+=int(packet.faces.get("unresolved_wet_cells",0))
  var positions:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for vertex_index in positions.size():positions[vertex_index]+=packet.origin
  for i in range(0,positions.size(),3):
   var a:Vector3=positions[i];var b:Vector3=positions[i+1];var c:Vector3=positions[i+2]
   if (c-a).cross(b-a).y<=0:continue
   var point:Vector3=(a+b+c)/3.0
   if point.x<41.5 or point.x>=42 or point.z<41.5 or point.z>=42:continue
   var actual:Dictionary=water.cell_geometry(Vector3(point.x,41.75,point.z))
   top_samples+=1;above_floor=above_floor and point.y>=actual.bottom-0.00001
   minimum_clearance=minf(minimum_clearance,point.y-actual.bottom)
   var colors:PackedColorArray=packet.arrays[Mesh.ARRAY_COLOR]
   if colors.is_empty() or colors[i].r>.5:free_top_samples+=1
 print("CONTACT_CLEARANCE samples=",top_samples," free=",free_top_samples," minimum_m=",minimum_clearance)
 # Exact clipping must retain this thin corner water while leaving the peak
 # dry. Sampling used to omit it entirely; a full cell sheet is also incorrect.
 check(top_samples>0 and free_top_samples>0 and above_floor and unresolved==0,"Thin corner water is rendered above the exact terrain contact")
 check(not water.raycast_surface(Vector3(41.75,41.95,41.75),Vector3(41.75,41.51,41.75)).get("hit",false),"Exposed terrain peak has no fabricated water sheet")
 check(water.statistics().water_ml==29167,"Thin corner boundary preserves every stored millilitre")
 var resolved:=data.duplicate();resolved.encode_u64(16,80000);resolved.encode_u64(base+20+cell*12,80000)
 check(water.restore_snapshot(resolved),"Resolved partial contact volume restores")
 var resolved_tops:=0;var excludes_peak:=true
 for step in 100:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  var positions:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,positions.size(),3):
   var a:Vector3=positions[i]+packet.origin;var b:Vector3=positions[i+1]+packet.origin;var c:Vector3=positions[i+2]+packet.origin
   if (c-a).cross(b-a).y<=0:continue
   var point:Vector3=(a+b+c)/3.0
   if point.x<41.5 or point.x>=42 or point.z<41.5 or point.z>=42:continue
   var actual:Dictionary=water.cell_geometry(Vector3(point.x,41.75,point.z))
   resolved_tops+=1;excludes_peak=excludes_peak and point.y>=actual.bottom-.00001
 check(resolved_tops>0 and excludes_peak,"Resolved free surface respects the interior terrain peak")
 check(water.statistics().water_ml==80000,"Contact clipping does not delete stored water")
 var gradient:=data.duplicate();var gradient_total:=0
 for z in range(2,5):
  for x in range(2,5):
   var i:=x+8*3+64*z;var amount:=41667 if x==3 and z==3 else 62500+(x-3)*3000+(z-3)*2000
   gradient.encode_u64(base+20+i*12,amount);gradient_total+=amount
 gradient.encode_u64(16,gradient_total)
 check(water.restore_snapshot(gradient),"Unequal surrounding heads meet an exact interior terrain peak")
 var contact_audit:Dictionary=load("res://tests/water_pool_topology.gd").audit(water)
 check(contact_audit.failures==0,"Reconstructed sloping water remains closed at exact terrain contacts: "+str(contact_audit))
 check(water.restore_snapshot(gradient),"Contact-gradient occupancy restores for clearance checks")
 var gradient_samples:=0;var gradient_clear:=true
 for step in 100:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,vertices.size(),3):
   var a:Vector3=vertices[i]+packet.origin;var b:Vector3=vertices[i+1]+packet.origin;var c:Vector3=vertices[i+2]+packet.origin
   if (c-a).cross(b-a).y<=0:continue
   var point:Vector3=(a+b+c)/3
   if point.x<41.5 or point.x>=42 or point.z<41.5 or point.z>=42:continue
   gradient_samples+=1;gradient_clear=gradient_clear and point.y>=water.cell_geometry(Vector3(point.x,41.75,point.z)).bottom-.00001
 check(gradient_samples>0 and gradient_clear,"Sloping free-surface triangles remain above the exact contact floor")
 check(water.statistics().water_ml==gradient_total,"Contact-gradient reconstruction preserves exact stored quantity")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_contact_volume.json",FileAccess.WRITE);report.store_string(JSON.stringify({"failures":failures,"cases":9}));report.close()
 print("WATER_CONTACT_VOLUME failures=",failures);quit(failures)
