# SPDX-License-Identifier: 0BSD
extends "res://tests/road_vegetation.gd"
func run() -> void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
 var ground:=sample(core,PackedVector3Array([Vector3(808.25,0,1304.25)]))
 var center: Vector3=ground.points[0]
 check(Codec.reply_ok(core.execute(Codec.graded_bed(center-Vector3(4,0,0),center+Vector3(4,0,0),3,8,12,4))),"pave through natural surface height")
 var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
 var mesh: Dictionary=Codec.decode_mesh(core.build_owned_region(800,1296,16,1,floori(center.y/32)*32,floori(center.y/32)*32+32,epoch))
 if not check_mesh(mesh):quit(1);return
 var vertices: PackedVector3Array=mesh.arrays[Mesh.ARRAY_VERTEX]
 var uv: PackedVector2Array=mesh.arrays[Mesh.ARRAY_TEX_UV2]
 var colors: PackedColorArray=mesh.arrays[Mesh.ARRAY_COLOR]
 var checked:=0;var minimum:=1.0;var valid:=true
 for i in vertices.size():
  var asphalt: float=(uv[i].y-floorf(uv[i].y))*4
  valid=valid and asphalt>=0 and asphalt<=1 and colors[i].r+colors[i].g+colors[i].b+asphalt<=1.0001
  if absf(vertices[i].x-center.x)<1.5 and absf(vertices[i].z-center.z)<1.5 and absf(vertices[i].y-center.y)<.2:
   checked+=1;minimum=minf(minimum,asphalt)
 print("surface samples=",checked," minimum asphalt=",minimum)
 check(checked>=4 and minimum>.95,"unchanged-height road interior remains fully asphalt")
 check(valid,"material weights remain normalized")
 var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
 var restored=ClassDB.instantiate("TerrainCore")
 var packet:=Codec.command(5);packet.append_array(saved)
 check(Codec.reply_ok(restored.execute(packet)),"paved terrain snapshot restores")
 var restored_epoch: int=restored.execute(Codec.command(13)).decode_u32(12)
 var restored_mesh: Dictionary=Codec.decode_mesh(restored.build_owned_region(800,1296,16,1,floori(center.y/32)*32,floori(center.y/32)*32+32,restored_epoch))
 check(restored_mesh.get("arrays",[] )==mesh.arrays,"restored pavement reproduces exact mesh and material weights")
 check(Codec.reply_ok(core.execute(Codec.graded_bed(center-Vector3(4,0,0),center+Vector3(4,0,0),3,8,12,1))),"repaint same geometry as stone")
 epoch=core.execute(Codec.command(13)).decode_u32(12)
 var stone: Dictionary=Codec.decode_mesh(core.build_owned_region(800,1296,16,1,floori(center.y/32)*32,floori(center.y/32)*32+32,epoch))
 var no_asphalt:=true
 if check_mesh(stone):
  for channel: Vector2 in stone.arrays[Mesh.ARRAY_TEX_UV2]:
   if channel.y-floorf(channel.y)>.0001:no_asphalt=false
 check(no_asphalt,"stone replacement removes asphalt colour")
 print("ROAD_SURFACE_PAINT failures=",failures)
 quit(1 if failures else 0)

func check_mesh(mesh: Dictionary) -> bool:
 var ok:=mesh.has("arrays")
 check(ok,"native mesh response valid")
 return ok
