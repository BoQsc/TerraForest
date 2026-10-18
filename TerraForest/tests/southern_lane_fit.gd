# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Districts=preload("res://addons/structures/regional_districts.gd")
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var sources:Array[Resource]=[preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage(),preload("res://addons/structures/workshop_catalog.gd").workshop()]
 var plan:Dictionary=Districts.plan(4);var failures:=0;var rows:Array=[]
 for seed_value in [0,1,42,50,141,1703,9999]:
  var mixed:Dictionary=Districts.mixed_layout_seed(sources,seed_value+4,plan.lots,plan.streets)
  if not mixed.get("ok",false):failures+=1;continue
  var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
  if not asset.compose_frontage(sources,plan.lots,plan.width,plan.gap,mixed.seed):failures+=1;continue
  asset.set_meta("frontage_version",1);asset.set_meta("street_width",plan.width);asset.set_meta("entrance_paths",true)
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13)
  var center:Vector3=layout.sites[4].position
  var origin:Vector3i=preload("res://addons/structures/site_plan.gd").regional_origin(asset,center)
  var points:PackedVector3Array=asset.foundation_samples(origin,0,0)
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,13]))
  var low:=INF;var high:=-INF
  for offset in range(0,points.size(),64):
   var batch:PackedVector3Array=points.slice(offset,mini(offset+64,points.size()))
   var packet:=Codec.command(17,[batch.size()]);packet.append_array(batch.to_byte_array());var reply:PackedByteArray=core.execute(packet)
   if not Codec.reply_ok(reply):failures+=1;continue
   for i in batch.size():low=minf(low,reply.decode_float(20+i*12));high=maxf(high,reply.decode_float(20+i*12))
  var quality:Dictionary=preload("res://addons/world_runtime/world_building_quality.gd").site({"ok":true,"grade":center.y,"min_height":low,"max_height":high},"Southern homes/workshop")
  var grading:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,center.y)
  var doors:=0
  for model:Dictionary in asset.get_model_attachments():
   if model.model=="architecture/wooden_door/v1":doors+=1
  var ok:bool=quality.status=="pass" and grading.ok and doors==4 and grading.get("entrance_paths",0)==4
  if not ok:failures+=1
  rows.append({"seed":seed_value,"layout_seed":mixed.seed,"quality":quality,"doors":doors,"ok":ok})
 FileAccess.open("res://reports/southern_lane_fit.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 print("SOUTHERN_LANE_FIT failures=",failures);quit(1 if failures else 0)
