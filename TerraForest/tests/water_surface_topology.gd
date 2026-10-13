# SPDX-License-Identifier: 0BSD
extends SceneTree
# Replay the actual runtime mesh, without diagnostic-only extra faces. A closed
# material envelope must pair each directed edge with its reverse across packets.
# This deliberately does not infer visible continuity from stored-cell adjacency.
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var water=ClassDB.instantiate("NativeRegionalWater")
 var state:=FileAccess.get_file_as_bytes("res://tests/fixtures/water_contact_clip/captured.bin")
 if not water.restore_snapshot(state):push_error("Fixture restore failed");quit(1);return
 var edges:Dictionary={};var triangles:=0;var degenerate:=0;var longest:=0.0
 var signed_volume:=0.0;var volume_origin:=Vector3(800,48,1300)
 var stored:int=water.statistics().water_ml
 for iteration in 10000:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,vertices.size(),3):
   var a:Vector3=vertices[i];var b:Vector3=vertices[i+1];var c:Vector3=vertices[i+2]
   triangles+=1
   signed_volume+=(a-volume_origin).dot((b-volume_origin).cross(c-volume_origin))/6.0
   if (b-a).cross(c-a).length_squared()<1e-16:degenerate+=1
   for j in 3:
    var u:Vector3=vertices[i+j];var v:Vector3=vertices[i+(j+1)%3]
    longest=maxf(longest,u.distance_to(v))
    # Exact float positions are intentional: neighbouring packets must share
    # identical extraction inputs and intersections, not merely look close.
    var forward:bool=u.x<v.x or (u.x==v.x and (u.y<v.y or (u.y==v.y and u.z<v.z)))
    var key:Array=[u,v] if forward else [v,u]
    var row:Vector2i=edges.get(key,Vector2i.ZERO)
    row.x+=1;row.y+=1 if forward else -1;edges[key]=row
 var unpaired:=0;var nonmanifold:=0;var winding:=0;var examples:Array=[]
 var boundary:Array=[];var bins:Dictionary={}
 for edge:Array in edges:
  var row:Vector2i=edges[edge]
  if row.x==1:
   unpaired+=1
   var segment:int=boundary.size();boundary.append(edge)
   var low:=Vector3i((edge[0].min(edge[1])*2).floor())-Vector3i.ONE
   var high:=Vector3i((edge[0].max(edge[1])*2).floor())+Vector3i.ONE
   for z in range(low.z,high.z+1):
    for y in range(low.y,high.y+1):
     for x in range(low.x,high.x+1):
      var cell:=Vector3i(x,y,z)
      if not bins.has(cell):bins[cell]=[]
      bins[cell].append(segment)
   if examples.size()<32:examples.append({"a":edge[0],"b":edge[1]})
  elif row.x!=2:nonmanifold+=1
  elif row.y!=0:winding+=1
 # Separate visible-scale gaps from exact-float mismatches and T-junctions.
 # This is a boundary diagnostic, not a proof of watertightness or coverage.
 var unmatched_midpoints:=0;var unmatched_length:=0.0;var gap_examples:Array=[]
 for i in boundary.size():
  var edge:Array=boundary[i];var point:Vector3=(edge[0]+edge[1])*0.5
  var vector:Vector3=edge[1]-edge[0]
  if vector.length()<0.002:continue
  var matched:=false
  for j:int in bins.get(Vector3i((point*2).floor()),[]):
   if i==j:continue
   var other:Array=boundary[j];var direction:Vector3=other[1]-other[0]
   if direction.length_squared()<1e-16:continue
   if absf(vector.normalized().dot(direction.normalized()))<0.99:continue
   var t:=clampf((point-other[0]).dot(direction)/direction.length_squared(),0,1)
   if point.distance_to(other[0]+direction*t)<=0.001:matched=true;break
  if not matched:
   unmatched_midpoints+=1;unmatched_length+=vector.length()
   if gap_examples.size()<32:gap_examples.append({"a":edge[0],"b":edge[1]})
 var passed:bool=triangles>0 and unpaired==0 and nonmanifold==0 and winding==0 and degenerate==0 and water.statistics().water_ml==stored
 var result:Dictionary={"failures":0 if passed else 1,"triangles":triangles,"unpaired_edges":unpaired,"nonmanifold_edges":nonmanifold,"same_direction_pairs":winding,"degenerate_triangles":degenerate,"longest_edge_m":longest,"water_ml":stored,"examples":examples,"scope":"Exact edge conformity of the complete captured material envelope; unpaired edges may include T-junctions and require geometric diagnosis."}
 result.unmatched_midpoints_1mm=unmatched_midpoints;result.unmatched_edge_length_m=unmatched_length;result.gap_examples=gap_examples
 result.signed_volume_m3=signed_volume
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_surface_topology.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 var summary:Dictionary=result.duplicate();summary.erase("examples");summary.erase("gap_examples")
 print("WATER_SURFACE_TOPOLOGY ",JSON.stringify(summary));quit(result.failures)
