# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
func _initialize()->void:
 var failures:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,13]))
  var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13).sites[3].position
  var bay:Dictionary=Lots.parking(center)
  var points:PackedVector3Array=bay.probe.foundation_samples(Vector3i(center),0,0)
  var low:=INF;var high:=-INF
  for offset in range(0,points.size(),64):
   var batch:=points.slice(offset,mini(offset+64,points.size()));var command:=Codec.command(17,[batch.size()]);command.append_array(batch.to_byte_array())
   var reply:PackedByteArray=core.execute(command)
   if not Codec.reply_ok(reply):failures+=1;continue
   for i in batch.size():low=minf(low,reply.decode_float(20+i*12));high=maxf(high,reply.decode_float(20+i*12))
  var quality:Dictionary=preload("res://addons/world_runtime/world_building_quality.gd").site({"ok":is_finite(low) and is_finite(high),"min_height":low,"max_height":high,"grade":center.y},"Northern parking bay")
  print("BAY_FIT seed=",seed_value," quality=",quality)
  if quality.status!="pass":failures+=1
  for lot:Dictionary in Lots.recipe(center):
   if lot.asset.placement_bounds(lot.origin,lot.rotation).intersects(bay.bounds):print("BAY_STRUCTURE_OVERLAP ",lot.label);failures+=1
  # Body is off the through-road and well away from loop intersection turns.
  if absf(bay.pose.origin.x-center.x)-3.25<4.5 or bay.pose.origin.z-center.z<60:failures+=1
 print("NEIGHBORHOOD_PARKING_FIT failures=",failures)
 quit(1 if failures else 0)
