# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var results:Dictionary={"cases":[]}
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fresh():
 var core=ClassDB.instantiate("TerrainCore")
 core.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
 return core
func measure(core)->Dictionary:
 var reply:PackedByteArray=core.execute(Codec.command(1,[16,16,32,1]))
 var nv:int=reply.decode_u32(40);var ni:int=reply.decode_u32(44)
 var vertices:PackedVector3Array=Codec._packed_channel(reply,52,nv,12,TYPE_PACKED_VECTOR3_ARRAY)
 var ids:PackedInt32Array=Codec._packed_channel(reply,52+nv*56,ni,4,TYPE_PACKED_INT32_ARRAY)
 var volume:=0.0
 for i in range(0,ni,3):
  var a:=vertices[ids[i]]-Vector3(16,8,16);var b:=vertices[ids[i+1]]-Vector3(16,8,16);var c:=vertices[ids[i+2]]-Vector3(16,8,16)
  volume+=a.dot(b.cross(c))/6.0
 return {"volume_m3":absf(volume),"triangles":ni/3,"mesh":reply.slice(52)}
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 for x:int in [24,31,32]:
  var core=fresh();var neighbour=fresh()
  check(Codec.reply_ok(core.execute(Codec.command(3,[x,12,24,1]))),"Place one existing terrain voxel at x=%d"%x)
  var single:=measure(core)
  check(absf(single.volume_m3-1.0)<0.00001 and single.triangles==12,"Terrain voxel renders one cubic metre with twelve triangles")
  core.execute(Codec.command(3,[x+1,12,24,1]));neighbour.execute(Codec.command(3,[x+1,12,24,1]))
  var joined:=measure(core)
  check(absf(joined.volume_m3-2.0)<0.00001,"Adjacent unit adds exactly one cubic metre")
  core.execute(Codec.command(3,[x,12,24,0]))
  var remaining:=measure(core)
  check(remaining.mesh==measure(neighbour).mesh,"Removing one unit leaves neighbouring geometry unchanged")
  var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
  var restored=fresh();var load_packet:=Codec.command(5);load_packet.append_array(saved)
  check(Codec.reply_ok(restored.execute(load_packet)) and measure(restored).mesh==remaining.mesh,"Existing terrain archive preserves fixed-unit geometry")
  var cached:PackedByteArray=core.execute(Codec.command(20,[16,16,32,1]))
  check(cached.slice(52)==remaining.mesh,"Existing terrain cache produces identical voxel geometry")
  var state:PackedByteArray=core.execute(Codec.command(0))
  check(state.decode_u32(20)==0,"Fixed voxel ownership requires no allocated density pages")
  results.cases.append({"x":x,"single_m3":single.volume_m3,"single_triangles":single.triangles,"joined_m3":joined.volume_m3,"joined_triangles":joined.triangles,"neighbour_restored":remaining.mesh==measure(neighbour).mesh})
 results.failures=failures
 results.scope="Existing TerrainCore voxel storage, renderer, cache and archive only. No live water replacement, terrain contact, transparent shading or water gameplay acceptance. Smooth density-box failure remains separate."
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/terrain_material_units.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 print("TERRAIN_MATERIAL_UNITS failures=",failures);quit(failures)
