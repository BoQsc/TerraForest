extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Digest=preload("res://addons/world_runtime/survey_cache.gd")
const REFERENCE:="user://terrain_map_efficiency_reference.json"
func _initialize()->void:
 var records:Array=[]
 var failures:=0
 for seed_value in [0,42,1703]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,23]))
  var points:=PackedVector3Array()
  for depth in range(50,1951,100):
   for across in range(50,1951,100):
    var point:=Vector3(across+.25,0,depth+.75)
    var height:float=core.execute(Codec.point_command(point)).decode_float(12)
    point.y=height+float((across/100)%3-1)*4;points.append(point)
  var center:=Vector3(1005.25,0,1005.75)
  center.y=core.execute(Codec.point_command(center)).decode_float(12)
  for phase in 3:
   if phase==1:core.execute(Codec.brush(center+Vector3.UP*12,center+Vector3.UP*12,5,1,true,3))
   if phase==2:core.execute(Codec.brush(center-Vector3.UP*8,center+Vector3.UP*16,6,1,false,3))
   var probes:=points.duplicate()
   for height in range(floori(center.y)-12,ceili(center.y)+20):probes.append(Vector3(center.x,height,center.z))
   var visibility:=PackedByteArray();var calls:=0;var started:=Time.get_ticks_usec()
   while visibility.size()<probes.size():
    var reply:Dictionary=core.survey_water_visibility(probes.slice(visibility.size(),mini(visibility.size()+256,probes.size())))
    if not reply.get("ok",false) or reply.visible.is_empty():failures+=1;break
    visibility.append_array(reply.visible);calls+=1
   var visibility_ms:float=(Time.get_ticks_usec()-started)/1000.0
   var patches:=PackedByteArray();started=Time.get_ticks_usec()
   for offset in range(112,145,4):
    var patch:Dictionary=core.survey_patch(256,offset,offset,4,4)
    if not patch.get("ok",false):failures+=1;break
    patches.append_array(patch.pixels)
   records.append({"seed":seed_value,"phase":phase,"visible":Digest.digest(visibility).hex_encode(),"pixels":Digest.digest(patches).hex_encode(),"visibility_ms":visibility_ms,"patch_ms":(Time.get_ticks_usec()-started)/1000.0,"calls":calls})
 if "--reference" in OS.get_cmdline_user_args():
  FileAccess.open(REFERENCE,FileAccess.WRITE).store_string(JSON.stringify(records))
 else:
  var previous=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/terrain_map_reference.json"))
  if not previous is Array or previous.size()!=records.size():failures+=1
  else:
   for index in records.size():
    for key:String in ["seed","phase","visible","pixels"]:
     if previous[index][key]!=records[index][key]:failures+=1;print("MAP_DIFFERENCE ",index," ",key)
  DirAccess.make_dir_recursive_absolute("res://reports/map_efficiency")
  FileAccess.open("res://reports/map_efficiency/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"before":previous,"after":records},"  "))
 print("TERRAIN_MAP_EFFICIENCY failures=",failures," records=",records);quit(1 if failures else 0)
