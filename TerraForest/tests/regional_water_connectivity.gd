# SPDX-License-Identifier: 0BSD
extends SceneTree
# Codec-backed regression: adjacent cells with disjoint vertical air intervals
# must not become connected just because both contain air. The actual-world
# acceptance test remains regional_water_world.gd.
func fixture(floor_b:int,ceiling_b:int) -> RefCounted:
 var catalog=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var data:=PackedByteArray();data.resize(32+catalog.size()+16+512*12);data.fill(0)
 data.encode_u32(0,0x31575256);data.encode_u32(4,1);data.encode_u32(8,catalog.size());data.encode_u32(12,1)
 for i in catalog.size():data[32+i]=catalog[i]
 var base:int=32+catalog.size();data.encode_u64(base,(10<<24)|(10<<12)|10);data.encode_u32(base+8,1);base+=16
 for i in 512:data.encode_u16(base+i*12,500);data.encode_u16(base+i*12+2,500)
 var a:int=3+8*3+64*3;var b:=a+1
 data.encode_u16(base+a*12,300);data.encode_u16(base+a*12+2,500)
 data.encode_u16(base+b*12,floor_b);data.encode_u16(base+b*12+2,ceiling_b)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(data):return null
 if not water.begin_fill(AABB(Vector3(40,40,40),Vector3(4,4,4)),41.95,Vector3(41.75,41.9,41.75),-1):return null
 for i in 4:water.advance(2048)
 return water
func _initialize():
 var disconnected=fixture(0,200);var connected=fixture(250,500)
 var failures:=0
 var ok:bool=disconnected!=null and disconnected.statistics().water_ml==37500 and disconnected.depth_at(Vector3(42.25,41.6,41.75))==0
 print("PASS " if ok else "FAIL ","Disconnected air intervals cannot create water across a solid gap");failures+=int(not ok)
 ok=connected!=null and connected.statistics().water_ml==87500 and connected.depth_at(Vector3(42.25,41.9,41.75))>0
 print("PASS " if ok else "FAIL ","An actual shared opening fills both cells with exact capacity");failures+=int(not ok)
 print("REGIONAL_CONNECTIVITY failures=",failures);quit(failures)
