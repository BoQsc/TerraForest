# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var water=ClassDB.instantiate("NativeRegionalWater")
 assert(water.restore_snapshot(FileAccess.get_file_as_bytes("res://tests/fixtures/water_pool_topology/recovery.bin")))
 var edges:Dictionary={};var failures:=0
 while true:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  var v:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,v.size(),3):
   if ((v[i]+v[i+1]+v[i+2])/3.0).distance_to(Vector3(800,49.68257,1308.438))>4:continue
   for j in 3:
    var a:Vector3=v[i+j];var b:Vector3=v[i+(j+1)%3]
    var forward:bool=a.x<b.x or (a.x==b.x and (a.y<b.y or (a.y==b.y and a.z<b.z)))
    var key:Array=[a,b] if forward else [b,a]
    edges[key]=int(edges.get(key,0))+1
 print("EDGES ",edges.size())
 for edge:Array in edges:
  if edges[edge]==2:continue
  failures+=1
  print("EDGE ",edge," count=",edges[edge])
  for vertex:Vector3 in edge:
   var cell:=((vertex-Vector3.ONE*0.125)/0.25).floor();var signs:=0
   for i in 8:
    var node:Vector3=(cell+Vector3(i&1,(i>>1)&1,(i>>2)&1))*0.25+Vector3.ONE*0.125
    if water.depth_at(node)>0:signs|=1<<i
   print("CELL ",cell," signs=",signs)
 if edges.is_empty():failures+=1
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_pool_topology.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"edges":edges.size()}));report.close()
 print("WATER_POOL_TOPOLOGY failures=",failures)
 quit(failures)
