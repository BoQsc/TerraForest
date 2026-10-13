# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func triangles(bytes:PackedByteArray,vertex_at:int,count:int,index_at:int,indices:int) -> Dictionary:
 var result:Dictionary={}
 for i in range(0,indices,3):
  var keys:Array[String]=[];var center:=Vector3.ZERO
  for j in 3:
   var at:int=vertex_at+12*bytes.decode_u32(index_at+4*(i+j))
   keys.append(bytes.slice(at,at+12).hex_encode())
   center+=Vector3(bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8))/3.0
  if not AABB(Vector3(808,28,1304),Vector3(4,4,4)).has_point(center):continue
  # Preserve winding while allowing a cyclic first vertex.
  var a:=keys[0]+keys[1]+keys[2];var b:=keys[1]+keys[2]+keys[0];var c:=keys[2]+keys[0]+keys[1]
  var options:Array[String]=[a,b,c];options.sort();result[options[0]]=true
 return result
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,3]))
 core.execute(Codec.brush(Vector3(810,30,1306),Vector3(810,30,1306),2,0,false,3))
 var revision:int=core.execute(Codec.command(0)).decode_u32(12)
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var packet:=Codec.command(32,[revision,epoch,808,28,1304])
 var boundary:PackedByteArray=core.execute(packet)
 check(Codec.reply_ok(boundary),"Terrain worker exports its existing material boundary")
 if not Codec.reply_ok(boundary):quit(1);return
 var full:PackedByteArray=core.execute(Codec.command(1,[800,1296,32,1,epoch]))
 check(Codec.reply_ok(full),"Ordinary full-detail terrain mesh is available as independent packet oracle")
 var expected:=triangles(full,52,full.decode_u32(40),52+56*full.decode_u32(40),full.decode_u32(44))
 var actual:=triangles(boundary,28,boundary.decode_u32(20),28+12*boundary.decode_u32(20),boundary.decode_u32(24))
 check(expected.size()>0 and expected==actual,"Boundary triangles and winding exactly match ordinary terrain inside the requested region")
 check(boundary==core.execute(packet),"Repeated boundary request is deterministic and read-only")
 packet.encode_u32(4,revision+1)
 check(core.execute(packet).decode_u32(8)==4,"Stale density revision returns no geometry")
 packet.encode_u32(4,revision);packet.encode_u32(8,epoch+1)
 check(core.execute(packet).decode_u32(8)==4,"Cancelled boundary request returns no geometry")
 packet.encode_u32(8,epoch);packet.encode_u32(12,809)
 check(core.execute(packet).decode_u32(8)==1,"Unaligned region is rejected")
 print("TERRAIN_MATERIAL_BOUNDARY triangles=",actual.size()," failures=",failures)
 quit(failures)
