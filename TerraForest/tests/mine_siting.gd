extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var c=ClassDB.instantiate("TerrainCore")
 for seed_value in [1703,1,42,9999]:
  c.execute(Codec.command(6,[seed_value,10]))
  var d:PackedByteArray=c.execute(Codec.command(35))
  var e:=Vector3(d.decode_float(32),d.decode_float(36),d.decode_float(40))
  for sign_value in [-1,1]:
   var lowest:=255.0
   for x in range(125,211,4):
    for z in range(-50,36,4):
     var p:=e+Vector3(sign_value*x,0,z)
     lowest=minf(lowest,c.execute(Codec.point_command(p)).decode_float(12))
   print("SITING seed=",seed_value," side=",sign_value," owner=",e.y," low=",lowest)
 print("MINE_SITING done");quit()
