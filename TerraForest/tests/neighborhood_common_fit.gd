# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Common=preload("res://addons/structures/neighborhood_common.gd")
func _initialize()->void:
 var failures:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13).sites[3].position
  var common:Dictionary=Common.build(center)
  if not common.ok:failures+=1;continue
  var records:PackedInt32Array=common.asset.get_records();var cells:Dictionary={}
  for i in range(0,records.size(),4):cells[Vector2i(records[i],records[i+2])]=true
  # Every paved tile is reachable from the existing southern street sidewalk.
  var pending:Array[Vector2i]=[Vector2i(-7,4)];var visited:Dictionary={}
  while not pending.is_empty():
   var at:Vector2i=pending.pop_back()
   if visited.has(at) or not cells.has(at):continue
   visited[at]=true
   for step:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:pending.append(at+step)
  if visited.size()!=cells.size() or not visited.has(Vector2i(-7,47)):failures+=1
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,13]))
  var low:=INF;var high:=-INF
  var points:PackedVector3Array=common.asset.foundation_samples(common.origin,0,0)
  for offset in range(0,points.size(),64):
   var batch:=points.slice(offset,mini(offset+64,points.size()));var command:=Codec.command(17,[batch.size()]);command.append_array(batch.to_byte_array());var reply:PackedByteArray=core.execute(command)
   if not Codec.reply_ok(reply):failures+=1;continue
   for i in batch.size():low=minf(low,reply.decode_float(20+i*12));high=maxf(high,reply.decode_float(20+i*12))
  var quality:Dictionary=preload("res://addons/world_runtime/world_building_quality.gd").site({"ok":is_finite(low) and is_finite(high),"min_height":low,"max_height":high,"grade":center.y},"Northern common")
  if quality.status!="pass":failures+=1
  for lot:Dictionary in preload("res://addons/structures/northern_lots.gd").recipe(center):
   var box:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
   for cell:Vector2i in cells:
    var point:=Vector3(center.x+cell.x+0.5,box.position.y+0.5,center.z+cell.y+0.5)
    if box.has_point(point):print("COMMON_BUILDING_OVERLAP ",lot.label);failures+=1;break
  # Full support under each prop's mesh footprint, including each chair and chest.
  for item:Dictionary in common.asset.get_model_attachments():
   var mesh_path:String={"furniture/table/v1":"table_model","furniture/chair/v1":"chair_model","storage/wooden_chest/v1":"storage_chest_model"}.get(item.model,"")
   var file:String="res://addons/structures/prefabs/"+mesh_path+".tres"
   if not ResourceLoader.exists(file):print("COMMON_MESH_MISSING ",file);failures+=1;continue
   var bounds:AABB=item.transform*(load(file) as Mesh).get_aabb()
   for x in [bounds.position.x,bounds.end.x]:
    for z in [bounds.position.z,bounds.end.z]:
     if not cells.has(Vector2i(floori(x),floori(z))):failures+=1
  print("COMMON_FIT seed=",seed_value," quality=",quality," paving=",cells.size()," models=",common.asset.get_model_attachments().size())
 print("NEIGHBORHOOD_COMMON_FIT failures=",failures)
 quit(1 if failures else 0)
