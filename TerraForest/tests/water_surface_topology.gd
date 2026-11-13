# SPDX-License-Identifier: 0BSD
extends SceneTree
# Replay the runtime continuous boundary including its buried contacts.
# Closure is tested on the same geometry used for rendering and queries.
# This deliberately does not infer visible continuity from stored-cell adjacency.
func _initialize():call_deferred("run")
func relative(point:Array)->Vector3:
 return Vector3(point[0]-800.0,point[1]-48.0,point[2]-1300.0)
func area_squared(a:Array,b:Array,c:Array)->float:
 var ux:float=b[0]-a[0];var uy:float=b[1]-a[1];var uz:float=b[2]-a[2]
 var vx:float=c[0]-a[0];var vy:float=c[1]-a[1];var vz:float=c[2]-a[2]
 return pow(uy*vz-uz*vy,2)+pow(uz*vx-ux*vz,2)+pow(ux*vy-uy*vx,2)
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var water=ClassDB.instantiate("NativeRegionalWater")
 var fixture_path:="res://tests/fixtures/water_contact_clip/captured.bin"
 if OS.get_cmdline_user_args().has("--structure-contact-fixture"):fixture_path="res://docs/evidence/water_structure_replacement/cached_water.bin.gz"
 var state:=FileAccess.get_file_as_bytes(fixture_path)
 if fixture_path.ends_with(".gz"):state=state.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP)
 if not water.restore_snapshot(state):push_error("Fixture restore failed");quit(1);return
 if OS.get_cmdline_user_args().has("--fresh-structure"):
  var blocks=ClassDB.instantiate("NativeBlockWorld")
  if not blocks.set_cells(PackedInt32Array([796,47,1292,6])):push_error("Structure fixture failed");quit(1);return
  water.invalidate_buildings(AABB(Vector3(796,47,1292),Vector3.ONE))
  for n in 100:
   var request:Dictionary=water.next_request()
   if request.is_empty():break
   var patch=ClassDB.instantiate("NativeWaterTerrainPatch")
   var hulls:Dictionary=blocks.solid_hulls(AABB(Vector3(request.coordinate)*4,Vector3.ONE*4))
   if not patch.configure(request.coordinate) or not hulls.ok or not patch.set_structure_hulls(hulls.hulls) or not water.reuse_building_occupancy(patch):push_error("Fresh structure preparation failed");quit(1);return
   patch.prepare_cached()
   if not water.accept_patch(patch):push_error("Fresh structure acceptance failed");quit(1);return
  blocks.free();fixture_path+=" + freshly prepared sphere"
 var diagnostic:Array=[]
 var edges:Dictionary={};var triangles:=0;var degenerate:=0;var longest:=0.0;var small:=0;var touching_edges:=0
 var stalled:=0;var stalled_area:=0.0
 var primitive_ml:=0.0;var boundary_ml:=0.0
 var represented_ml:=0.0;var over_capacity_ml:=0
 var signed_volume:=0.0;var volume_origin:=Vector3(800,48,1300)
 var stored:int=water.statistics().water_ml
 for iteration in 10000:
  var packet:Dictionary=water.next_mesh(true)
  if packet.is_empty():break
  stalled+=packet.faces.get("stalled_polygons",0);stalled_area+=packet.faces.get("stalled_area",0.0)
  primitive_ml+=packet.faces.get("primitive_ml",0.0);boundary_ml+=packet.faces.get("boundary_ml",0.0);represented_ml+=packet.faces.get("represented_ml",0.0);over_capacity_ml+=packet.faces.get("over_capacity_ml",0)
  var local_vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  var vertices:=PackedVector3Array();var exact:Array=[];var origin:Vector3=packet.origin
  for point:Vector3 in local_vertices:
   var position:Array=[float(point.x)+float(origin.x),float(point.y)+float(origin.y),float(point.z)+float(origin.z)]
   exact.append(position);vertices.append(relative(position))
  for i in range(0,vertices.size(),3):
   var a:Vector3=vertices[i];var b:Vector3=vertices[i+1];var c:Vector3=vertices[i+2]
   triangles+=1
   if OS.get_cmdline_user_args().has("--dump-neighborhood") and (a+volume_origin).distance_to(Vector3(796.5,47.5,1292.5) if OS.get_cmdline_user_args().has("--fresh-structure") else Vector3(792.02,45.5,1289.52))<1.5:
    diagnostic.append({"owner":str(packet.owners[i/3]),"vertices":[exact[i],exact[i+1],exact[i+2]]})
   signed_volume+=a.dot(b.cross(c))/6.0
   var area:float=area_squared(exact[i],exact[i+1],exact[i+2])
   if area==0:degenerate+=1
   elif area<1e-16:small+=1
   for j in 3:
    var u:Array=exact[i+j];var v:Array=exact[i+(j+1)%3]
    longest=maxf(longest,relative(u).distance_to(relative(v)))
    # Exact float positions are intentional: neighbouring packets must share
    # identical extraction inputs and intersections, not merely look close.
    var forward:bool=u[0]<v[0] or (u[0]==v[0] and (u[1]<v[1] or (u[1]==v[1] and u[2]<v[2])))
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
   var low:=Vector3i((relative(edge[0]).min(relative(edge[1]))*2).floor())-Vector3i.ONE
   var high:=Vector3i((relative(edge[0]).max(relative(edge[1]))*2).floor())+Vector3i.ONE
   for z in range(low.z,high.z+1):
    for y in range(low.y,high.y+1):
     for x in range(low.x,high.x+1):
      var cell:=Vector3i(x,y,z)
      if not bins.has(cell):bins[cell]=[]
      bins[cell].append(segment)
   if examples.size()<32:examples.append({"a":edge[0],"b":edge[1]})
  elif row.x%2!=0:
   nonmanifold+=1
   examples.append({"a":edge[0],"b":edge[1],"count":row.x,"balance":row.y})
  elif row.x>2 and row.y==0:touching_edges+=1
  elif row.y!=0:winding+=1
 # Separate visible-scale gaps from exact-float mismatches and T-junctions.
 # This is a boundary diagnostic, not a proof of watertightness or coverage.
 var unmatched_midpoints:=0;var unmatched_length:=0.0;var gap_examples:Array=[]
 for i in boundary.size():
  var edge:Array=boundary[i];var point:Vector3=(relative(edge[0])+relative(edge[1]))*0.5
  var vector:Vector3=relative(edge[1])-relative(edge[0])
  if vector.length()<0.002:continue
  var matched:=false
  for j:int in bins.get(Vector3i((point*2).floor()),[]):
   if i==j:continue
   var other:Array=boundary[j];var direction:Vector3=relative(other[1])-relative(other[0])
   if direction.length_squared()<1e-16:continue
   if absf(vector.normalized().dot(direction.normalized()))<0.99:continue
   var t:=clampf((point-relative(other[0])).dot(direction)/direction.length_squared(),0,1)
   if point.distance_to(relative(other[0])+direction*t)<=0.001:matched=true;break
  if not matched:
   unmatched_midpoints+=1;unmatched_length+=vector.length()
   if gap_examples.size()<32:gap_examples.append({"a":edge[0],"b":edge[1]})
 var passed:bool=triangles>0 and unpaired==0 and nonmanifold==0 and winding==0 and degenerate==0 and water.statistics().water_ml==stored and not water.statistics().surface_budget_failed
 var result:Dictionary={"failures":0 if passed else 1,"triangles":triangles,"unpaired_edges":unpaired,"nonmanifold_edges":nonmanifold,"same_direction_pairs":winding,"degenerate_triangles":degenerate,"longest_edge_m":longest,"water_ml":stored,"examples":examples,"scope":"Exact edge conformity of the complete captured material envelope; unpaired edges may include T-junctions and require geometric diagnosis."}
 result.stalled_polygons=stalled;result.stalled_area=stalled_area
 result.surface_budget_failed=water.statistics().surface_budget_failed
 result.fixture=fixture_path
 result.small_nonzero_triangles=small;result.balanced_touching_edges=touching_edges
 result.unmatched_midpoints_1mm=unmatched_midpoints;result.unmatched_edge_length_m=unmatched_length;result.gap_examples=gap_examples
 result.primitive_ml=primitive_ml;result.boundary_ml=boundary_ml;result.signed_volume_m3=signed_volume;result.represented_ml=represented_ml;result.over_capacity_ml=over_capacity_ml
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_surface_topology.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 if not diagnostic.is_empty():
  var dump:=FileAccess.open("res://reports/water_boundary_neighborhood.json",FileAccess.WRITE);dump.store_string(JSON.stringify(diagnostic));dump.close()
 var summary:Dictionary=result.duplicate();summary.erase("examples");summary.erase("gap_examples")
 print("WATER_SURFACE_TOPOLOGY ",JSON.stringify(summary));quit(result.failures)
