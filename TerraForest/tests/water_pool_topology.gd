# SPDX-License-Identifier: 0BSD
extends SceneTree
const GRID:int=4194304
# Audit actual region-local float coordinates without first losing precision by
# adding a kilometre-scale origin into a single-precision Vector3. Integer keys
# retain every stored bit and require exact agreement across region boundaries.
static func audit(water)->Dictionary:
 var vertices:Dictionary={};var points:Array=[];var edges:Dictionary={};var triangle_keys:Dictionary={}
 var duplicates:=0;var triangles:=0;var degenerate:=0;var off_grid:=0;var volume:=0.0;var anchor:Array=[]
 while true:
  var packet:Dictionary=water.next_mesh(true)
  if packet.is_empty():break
  var v:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  var offset:Array=[roundi(float(packet.origin.x)*GRID),roundi(float(packet.origin.y)*GRID),roundi(float(packet.origin.z)*GRID)]
  for i in range(0,v.size(),3):
   var ids:Array[int]=[];var coords:Array=[]
   for j in 3:
    var local:Array=[float(v[i+j].x)*GRID,float(v[i+j].y)*GRID,float(v[i+j].z)*GRID]
    var key:Array=[]
    for axis in 3:
     if local[axis]!=float(roundi(local[axis])):off_grid+=1
     key.append(offset[axis]+roundi(local[axis]))
    if not vertices.has(key):vertices[key]=points.size();points.append(key)
    ids.append(vertices[key]);coords.append(key)
   if anchor.is_empty():anchor=coords[0]
   triangles+=1
   var triangle:Array=ids.duplicate();triangle.sort()
   if triangle_keys.has(triangle):duplicates+=1
   triangle_keys[triangle]=true
   var a:Array=coords[0];var b:Array=coords[1];var c:Array=coords[2]
   var u:Array=[b[0]-a[0],b[1]-a[1],b[2]-a[2]];var w:Array=[c[0]-a[0],c[1]-a[1],c[2]-a[2]]
   var cross:Array=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]]
   if cross[0]==0 and cross[1]==0 and cross[2]==0:degenerate+=1
   for axis in 3:volume-=float(a[axis]-anchor[axis])*float(cross[axis])/(6.0*GRID*GRID*GRID)
   for j in 3:
    var first:int=ids[j];var second:int=ids[(j+1)%3]
    var edge:Array=[mini(first,second),maxi(first,second)]
    var pair:Vector2i=edges.get(edge,Vector2i.ZERO);pair.x+=1;pair.y+=1 if first<second else -1;edges[edge]=pair
 var open_edges:=0;var samples:Array=[]
 for edge:Array in edges:
  var pair:Vector2i=edges[edge]
  if pair.x<2 or pair.x%2!=0 or pair.y!=0:
   open_edges+=1
   if samples.size()<16:
    var a:Array=points[edge[0]];var b:Array=points[edge[1]]
    samples.append({"a":[float(a[0])/GRID,float(a[1])/GRID,float(a[2])/GRID],"b":[float(b[0])/GRID,float(b[1])/GRID,float(b[2])/GRID],"count":pair.x,"orientation":pair.y})
 var state:Dictionary=water.statistics()
 var mesh_ok:bool=not state.surface_budget_failed and state.dirty_meshes==0
 return {"failures":int(open_edges>0 or degenerate>0 or duplicates>0 or triangles==0 or off_grid>0 or not mesh_ok),"mesh_complete":mesh_ok,"open_edges":open_edges,"degenerate":degenerate,"duplicate_triangles":duplicates,"off_grid_vertices":off_grid,"triangles":triangles,"volume_m3":absf(volume),"owned_m3":state.water_ml/1000000.0,"edge_samples":samples}
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var source:="res://tests/fixtures/water_pool_topology/recovery.bin"
 var evidence:=""
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--water-snapshot="):source=argument.trim_prefix("--water-snapshot=")
  if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(FileAccess.get_file_as_bytes(source)):
  print("WATER_POOL_TOPOLOGY failures=1 invalid snapshot");quit(1);return
 var report:Dictionary=audit(water);report.source=source
 if not evidence.is_empty():FileAccess.open(evidence.path_join("water_pool_topology.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
 var summary:Dictionary=report.duplicate();summary.erase("edge_samples")
 print("WATER_POOL_TOPOLOGY ",JSON.stringify(summary)," failures=",report.failures)
 quit(report.failures)
