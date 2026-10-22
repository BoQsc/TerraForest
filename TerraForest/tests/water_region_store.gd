# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func packet(amount:int)->PackedByteArray:
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var b:=PackedByteArray();b.resize(32+catalog.size()+9076+12);b.fill(0)
 b.encode_u32(0,0x31575256);b.encode_u32(4,10);b.encode_u32(8,catalog.size());b.encode_u32(12,1);b.encode_u64(16,amount);b.encode_u64(24,12)
 for i in catalog.size():b[32+i]=catalog[i]
 var at:=32+catalog.size();b.encode_u64(at,(1<<24)|(9<<12)|250);b.encode_u32(at+8,1);b.encode_u32(at+12,9)
 for i in 512:b.encode_u16(at+16+i*12+2,500)
 b.encode_u64(at+20,amount)
 for i in 729:b.encode_float(at+6160+i*4,1.0)
 return b
func _initialize()->void:
 var folder:=ProjectSettings.globalize_path("user://water_store_check_"+str(Time.get_ticks_usec()))
 var store=ClassDB.instantiate("NativeWaterRegionStore");var other=ClassDB.instantiate("NativeWaterRegionStore")
 check(store.open_store(folder),"isolated store opens")
 check(not other.open_store(folder),"second writer rejected")
 var p:=Vector3i(1,9,250);var keys:=PackedInt32Array([1,9,250])
 var original:PackedByteArray=packet(125000);var empty:PackedByteArray=packet(0)
 var first:Dictionary=store.publish_region(p,original);check(first.ok,"validated region flushed and published")
 if not first.ok:quit(1);return
 var old:Dictionary=store.publish_checkpoint(keys,[first.digest]);check(old.ok,"checkpoint published after blob")
 var second:Dictionary=store.publish_region(p,empty);check(second.ok,"empty override published")
 var current:Dictionary=store.publish_checkpoint(keys,[second.digest]);check(current.ok,"new checkpoint published")
 check(store.read_region(old.checkpoint,p).get("packet",PackedByteArray())==original,"old checkpoint remains immutable")
 check(store.read_region(current.checkpoint,p).get("packet",PackedByteArray())==empty,"new checkpoint retains empty override")
 check(not store.publish_checkpoint(PackedInt32Array([2,9,250]),[first.digest]).ok,"mismatched region cannot enter checkpoint")
 check(not store.publish_checkpoint(PackedInt32Array([1,9,250,1,9,250]),[first.digest,first.digest]).ok,"duplicate entries rejected")
 check(not store.publish_region(p,original.slice(0,20)).ok,"invalid packet rejected")
 store.close();check(other.open_store(folder),"store reopens after lease released")
 check(other.read_region(old.checkpoint,p).get("packet",PackedByteArray())==original,"reopened old checkpoint restores bytes")
 check(other.read_region(current.checkpoint,p).get("packet",PackedByteArray())==empty,"reopened new checkpoint restores bytes")
 var file:=FileAccess.open(folder.path_join(second.digest.hex_encode()+".water"),FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
 check(not other.read_region(current.checkpoint,p).ok,"corrupt blob rejected without regeneration")
 check(not other.publish_region(p,empty).ok,"corrupt existing identity is not silently overwritten")
 check(not other.publish_checkpoint(keys,[second.digest]).ok,"corrupt blob cannot publish a checkpoint")
 check(other.read_region(old.checkpoint,p).get("packet",PackedByteArray())==original,"failed newer data leaves prior checkpoint readable")
 var missing:PackedByteArray=first.digest.duplicate();missing[0]^=1
 check(not other.read_region(missing,p).ok,"missing checkpoint fails closed")
 other.close();print("WATER_REGION_STORE failures=",failures);quit(1 if failures else 0)

