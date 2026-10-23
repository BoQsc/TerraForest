# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,19]))
 var rows:Array=[];var edit_times:Array=[];var failures_at:=0
 var control:=Vector3(1000,0,1000);control.y=core.execute(Codec.point_command(control)).decode_float(12)
 for count in range(2049):
  if count in [0,64,256,1024,2048]:
   var stats:PackedByteArray=core.execute(Codec.command(0));var began:=Time.get_ticks_usec()
   var ray:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(control+Vector3.UP*3,control-Vector3.UP*3,256,0,true)))
   var ray_ms:=(Time.get_ticks_usec()-began)/1000.0
   check(ray.status=="hit","unmodified control ray remains valid")
   began=Time.get_ticks_usec();var saved:PackedByteArray=core.execute(Codec.command(4));var save_ms:=(Time.get_ticks_usec()-began)/1000.0
   var restored=ClassDB.instantiate("TerrainCore");var load_packet:=Codec.command(5);load_packet.append_array(saved.slice(12))
   began=Time.get_ticks_usec();var loaded:PackedByteArray=restored.execute(load_packet);var load_ms:=(Time.get_ticks_usec()-began)/1000.0
   check(Codec.reply_ok(loaded) and restored.execute(Codec.command(4))==saved,"exact terrain restore at "+str(count)+" edits")
   var fast_times:Array=[];var fast_saved:PackedByteArray
   for repeat in range(3):
    began=Time.get_ticks_usec();fast_saved=core.execute(Codec.command(4,[3]));fast_times.append((Time.get_ticks_usec()-began)/1000.0)
   fast_times.sort()
   check(Codec.reply_ok(fast_saved) and fast_saved.decode_u32(16)==3,"fast format explicitly tagged")
   load_packet=Codec.command(5);load_packet.append_array(fast_saved.slice(12))
   began=Time.get_ticks_usec();loaded=restored.execute(load_packet);var fast_load_ms:=(Time.get_ticks_usec()-began)/1000.0
   check(Codec.reply_ok(loaded) and restored.execute(Codec.command(4))==saved,"fast format exact terrain restore at "+str(count)+" edits")
   restored=null
   var recent:=edit_times.slice(maxi(0,edit_times.size()-64));recent.sort()
   rows.append({"attempted_edits":count,"pages":stats.decode_u32(20),"revision":stats.decode_u32(12),"raw_page_bytes":stats.decode_u32(20)*12288,"archive_bytes":saved.size(),"serialize_ms":save_ms,"crc_serialize_median_ms":fast_times[1],"crc_restore_ms":fast_load_ms,"restore_ms":load_ms,"control_query_ms":ray_ms,"control_status":ray.status,"recent_edit_median_ms":recent[recent.size()/2] if not recent.is_empty() else 0.0,"recent_edit_p95_ms":recent[int(recent.size()*.95)] if not recent.is_empty() else 0.0})
   print("HISTORY_SCALE ",JSON.stringify(rows.back()))
  if count==2048:break
  var location:=count*127%2304;var point:=Vector3(88+(location%48)*38,0,88+(location/48)*38)
  if Vector2(point.x-control.x,point.z-control.z).length_squared()<32*32:point.x+=19
  point.y=core.execute(Codec.point_command(point)).decode_float(12)-0.6
  var began:=Time.get_ticks_usec();var result:PackedByteArray=core.execute(Codec.brush(point,point,2.5,0,false,1));edit_times.append((Time.get_ticks_usec()-began)/1000.0)
  if not Codec.reply_ok(result):failures_at=count+1;check(false,"native edit rejected at history "+str(failures_at));break
 FileAccess.open("res://reports/terrain_history_scaling.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"first_rejection":failures_at,"rows":rows,"scope":"Native sparse terrain history across distributed 2.5m excavations; exact archive restore and native CPU timings only. No rendered interaction, disk flush, full world save or endurance qualification."},"  "))
 print("TERRAIN_HISTORY_SCALING failures=",failures);quit(1 if failures else 0)
