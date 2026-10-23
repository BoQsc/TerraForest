# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
 var route=preload("res://demo/cave_checkpoint.gd").route()
 var core=ClassDB.instantiate("TerrainCore");core.execute(codec.command(6,[1703,6]))
 var epoch=core.execute(codec.command(13)).decode_u32(12)
 for p in route.points:
  var roof=codec.decode_density_ray(core.execute(codec.density_ray_command(p+Vector3.UP*1.8,p+Vector3.UP*32,128,epoch,true)))
  print("CAVE_PROBE floor=",p," roof=",roof)
 quit()
