# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var rows:Array=[]
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(count:int):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+count*9076);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,count);bytes.encode_u64(16,count*4000000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 for r in count:
  var base:int=32+catalog.size()+r*9076;var rx:=10+3*(r/16);var rz:=10+3*(r%16)
  bytes.encode_u64(base,(rx<<24)|(10<<12)|rz);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1);base+=16
  for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
  for z in 8:
   for x in 8:
    var i:=x+8*3+64*z;bytes.encode_u16(base+i*12,0);bytes.encode_u64(base+i*12+4,62500)
  for i in 729:bytes.encode_float(base+6144+i*4,1.0)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):return null
 return water
func publish(water,limit:int) -> Dictionary:
 var started:=Time.get_ticks_usec();var packets:=0;var empty:=0;var commit_us:=0;var complete:=false
 for step in limit:
  var packet:Dictionary=water.next_mesh_batch()
  if packet.is_empty():break
  if packet.has("coordinate"):
   packets+=1
   if packet.vertices==0:empty+=1
  if packet.complete:
   var mark:=Time.get_ticks_usec();complete=water.commit_mesh_batch(packet.batch);commit_us=Time.get_ticks_usec()-mark;break
 return {"complete":complete,"packets":packets,"empty_packets":empty,"native_us":Time.get_ticks_usec()-started,"commit_us":commit_us,"minimum_frames_at_four_packets":ceili(packets/4.0)}
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 for count in [1,16,64,256]:
  var water=fixture(count)
  if water==null:quit(2);return
  var initial:=publish(water,count*28+32)
  var point:=Vector3(41.75,41.6,41.75)
  var edited:int=water.brush(point,0.0,1000)
  var local:=publish(water,100)
  var before:int=water.statistics().cell_steps;water.advance(1)
  var stats:Dictionary=water.statistics()
  check(initial.complete and local.complete and edited==1000 and stats.water_ml==count*4000000+1000,"Publication and local edit conserve water (%d regions)"%count)
  check(initial.packets<=count*4 and initial.empty_packets==0,"Restore schedules surface owners without empty halo packets (%d regions)"%count)
  check(local.packets==1,"Local interior edit rebuilds only one owner (%d regions)"%count)
  rows.append({"regions":count,"initial":initial,"local_edit":local,"query_cache_bytes":stats.query_cache_bytes,"resident_cell_bytes":stats.resident_cell_bytes})
 print("WATER_SCALE ",JSON.stringify(rows))
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_publication_scale.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"rows":rows},"  "));file.close()
 quit(failures)
