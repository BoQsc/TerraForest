# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture():
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,10000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1)
 for i in 512:bytes.encode_u16(base+16+i*12,500);bytes.encode_u16(base+18+i*12,500)
 var source:=3+8*3+64*3;var sink:=source+1
 bytes.encode_u16(base+16+source*12,100);bytes.encode_u64(base+20+source*12,10000|(1<<63))
 bytes.encode_u16(base+16+sink*12,0)
 var water=ClassDB.instantiate("NativeRegionalWater");water.restore_snapshot(bytes);return water
func sink_amount(water) -> int:
 var bytes:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
 return bytes.decode_u64(32+bytes.decode_u32(8)+20+(4+8*3+64*3)*12)&0x7fffffffffffffff
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var one=fixture();one.advance(8192,1.0/60.0)
 check(sink_amount(one)>0 and sink_amount(one)<1500,"One frame moves a limited fraction, not instantaneous equilibrium")
 var a=fixture();var b=fixture()
 for frame in 15:a.advance(8192,1.0/30.0)
 for frame in 60:b.advance(8192,1.0/120.0)
 var low:=sink_amount(a);var high:=sink_amount(b)
 check(abs(low-high)<=200,"Thirty and 120 Hz stay within 200 ml over the same half second")
 check(a.statistics().water_ml==10000 and b.statistics().water_ml==10000,"Time-based flow conserves every millilitre")
 var stalled=fixture();var bounded=fixture();stalled.advance(8192,5.0);bounded.advance(8192,0.05)
 check(sink_amount(stalled)==sink_amount(bounded),"Long frame stall is clamped to a 50 ms flow step")
 var invalid=fixture();invalid.advance(8192,0);invalid.advance(8192,-1);invalid.advance(8192,NAN)
 check(sink_amount(invalid)==0 and invalid.statistics().water_ml==10000,"Invalid elapsed time does not mutate water")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_flow_clock.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"first_frame_ml":sink_amount(one),"at_30hz_ml":low,"at_120hz_ml":high}));report.close()
 print("WATER_FLOW_CLOCK failures=",failures);quit(failures)
