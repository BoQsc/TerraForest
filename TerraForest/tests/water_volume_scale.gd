# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(width:int,height:int,amount_per_cell:int,sloped:bool=false):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+(9076 if sloped else 6160));bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2 if sloped else 1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1)
 bytes.encode_u64(16,width*width*height*amount_per_cell)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1)
 for i in 512:bytes.encode_u16(base+16+i*12,500);bytes.encode_u16(base+18+i*12,500)
 for z in range(2,2+width):
  for y in range(2,2+height):
   for x in range(2,2+width):
    var i:int=x+8*y+64*z
    bytes.encode_u16(base+16+i*12,0);bytes.encode_u64(base+20+i*12,amount_per_cell)
 if sloped:
  bytes.encode_u32(base+12,1)
  for i in 729:
   var x:float=40+(i%9)*0.5;var y:float=40+((i/9)%9)*0.5
   bytes.encode_float(base+6160+i*4,y-(41+(x-41)*0.5))
 var water=ClassDB.instantiate("NativeRegionalWater")
 assert(water.restore_snapshot(bytes))
 return water
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var results:Array=[]
 for dimensions in [Vector4i(2,2,125000,0),Vector4i(4,2,125000,0),Vector4i(1,1,125000,0),Vector4i(2,1,25000,0),Vector4i(1,1,1000,0),Vector4i(1,1,10000,1)]:
  var water=fixture(dimensions.x,dimensions.y,dimensions.z,dimensions.w!=0)
  var stored:int=water.statistics().water_ml
  var signed_volume:=0.0;var triangles:=0;var top:=-INF;var bottom:=INF
  var edges:Dictionary={}
  for iteration in 64:
   # Contacts close the same runtime reconstruction for the volume integral.
   # Runtime omits buried faces; this flag does not change vertex positions.
   var packet:Dictionary=water.next_mesh(true)
   if packet.is_empty():break
   var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
   for i in range(0,vertices.size(),3):
    var a:Vector3=vertices[i]-Vector3.ONE*41
    var b:Vector3=vertices[i+1]-Vector3.ONE*41
    var c:Vector3=vertices[i+2]-Vector3.ONE*41
    signed_volume+=a.dot(b.cross(c))/6.0;triangles+=1
    for e in 3:
     var v:Vector3=vertices[i+e];top=maxf(top,v.y);bottom=minf(bottom,v.y)
     var ka:=str(Vector3i((v*100000).round()))
     var kb:=str(Vector3i((vertices[i+(e+1)%3]*100000).round()))
     var key:String=ka+"/"+kb if ka<kb else kb+"/"+ka
     edges[key]=edges.get(key,0)+1
  var closed:bool=triangles>0
  for value:int in edges.values():closed=closed and value==2
  var visible_ml:float=abs(signed_volume)*1000000.0
  var relative_error:float=abs(visible_ml-stored)/stored
  var label:="%d x %d x %d cells, slope=%s"%[dimensions.x,dimensions.y,dimensions.x,dimensions.w!=0]
  check(closed,label+": measured envelope is closed")
  check(abs(top-bottom-((dimensions.y-1)*0.5+dimensions.z/250000.0+dimensions.w*0.25))<0.001,label+": rendered fill height matches world metres within 1 mm")
  check(relative_error<=0.01,label+": geometric volume agrees with stored volume within 1 percent")
  check(water.statistics().water_ml==stored,label+": measuring does not change water")
  var row:Dictionary={"dimensions":label,"stored_ml":stored,"mesh_ml":visible_ml,"relative_error":relative_error,"top":top,"bottom":bottom,"triangles":triangles,"closed":closed}
  results.append(row);print("VOLUME_SCALE ",JSON.stringify(row))
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_volume_scale.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"cases":results},"  "));file.close()
 print("WATER_VOLUME_SCALE failures=",failures);quit(failures)
