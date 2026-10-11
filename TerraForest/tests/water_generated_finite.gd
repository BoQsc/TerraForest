# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func v(data:PackedByteArray,offset:int)->Vector3:return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))
func _initialize():
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,4]))
 var definitions:PackedByteArray=core.execute(Codec.command(27));var epoch:int=core.execute(Codec.command(13)).decode_u32(12);var failed:=0
 for i in 4:
  var offset:=16+i*44;var runtime=ClassDB.instantiate("NativeWaterRuntime")
  var ok:bool=runtime.configure(v(definitions,offset),Vector3i(56,16,56),1.0,definitions.decode_float(offset+28),v(definitions,offset+32),PackedByteArray())
  var status:=0;var start:=Time.get_ticks_msec()
  while ok and status==0 and Time.get_ticks_msec()-start<10000:status=runtime.sample_terrain(core,512,0,epoch)
  print("GENERATED_FINITE ",i," ",runtime.statistics()," ms=",Time.get_ticks_msec()-start)
  if not ok or status!=1:failed+=1
  else:
   var network=runtime.get_network()
   if not network.probe(v(definitions,offset+32)).get("wet",false) or network.capture_state().is_empty():failed+=1
 print("GENERATED_FINITE failures=",failed);quit(int(failed!=0))
