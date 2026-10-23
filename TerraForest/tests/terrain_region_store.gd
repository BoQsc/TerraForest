# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func write(path:String,b:PackedByteArray)->void:
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(b);file.close()
func hash_bytes(b:PackedByteArray)->PackedByteArray:
 var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(b);return h.finish()
func run()->void:
 var path:=ProjectSettings.globalize_path("user://terrain_region_check_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var store=ClassDB.instantiate("NativeTerrainRegionStore")
 check(not store.open_store(path) and not DirAccess.dir_exists_absolute(path),"read-only open never creates missing storage")
 check(store.open_store(path,true),"new native terrain store opens for publication")
 var competing=ClassDB.instantiate("NativeTerrainRegionStore")
 check(not competing.open_store(path,true),"competing writer excluded by native lease")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,19]))
 for i in range(64):
  var p:=Vector3(808+(i%8)*80,0,808+(i/8)*80);p.y=core.execute(Codec.point_command(p)).decode_float(12)-0.6
  check(Codec.reply_ok(core.execute(Codec.brush(p,p,2.5,0,false,1))),"distributed edit %d"%i)
 var raw:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
 var began:=Time.get_ticks_usec();var reference:PackedByteArray=store.publish_snapshot(raw);var publish_ms:=(Time.get_ticks_usec()-began)/1000.0
 var first_stats:Dictionary=store.stats()
 check(reference.size()==40 and reference.slice(0,4).get_string_from_ascii()=="TFTR","terrain root becomes a 40-byte checkpoint reference")
 var description:Dictionary=store.describe_snapshot(reference)
 check(description.get("ok",false) and description.pages==raw.decode_u32(12) and description.generator==19,"checkpoint index preserves field metadata and page membership")
 began=Time.get_ticks_usec();var expanded:PackedByteArray=store.expand_snapshot(reference);var expand_ms:=(Time.get_ticks_usec()-began)/1000.0
 check(expanded==raw,"region expansion reconstructs exact native format 3 bytes")
 check(first_stats.written_bytes<raw.size()/2,"lossless page runs substantially reduce this edited-world fixture")
 var before:Dictionary=store.stats()
 check(store.publish_snapshot(raw,reference)==reference,"unchanged snapshot retains identical checkpoint identity")
 var after:Dictionary=store.stats()
 check(after.written_files==before.written_files and after.written_bytes==before.written_bytes,"unchanged save writes no region or index bytes")
 var p:=Vector3(808,0,808);p.y=core.execute(Codec.point_command(p)).decode_float(12)-2.0
 check(Codec.reply_ok(core.execute(Codec.brush(p,p,1.5,0,false,1))),"second local excavation admitted")
 var newer:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
 var next:PackedByteArray=store.publish_snapshot(newer,reference);var changed:Dictionary=store.stats();var changed_files:int=changed.written_files-after.written_files
 check(next!=reference and changed.written_files-after.written_files>0 and changed.written_files-after.written_files<=9,"local edit publishes only touched regions and new checkpoint")
 check(store.expand_snapshot(next)==newer and store.expand_snapshot(reference)==raw,"both immutable checkpoints remain exactly readable")
 var coordinates:PackedInt32Array=description.coordinates
 var coordinate:=Vector3i(coordinates[0],coordinates[1],coordinates[2]);before=store.stats()
 var region:Dictionary=store.read_region(reference,coordinate);after=store.stats()
 check(region.get("ok",false) and region.get("present",false) and region.pages.size()<=64 and after.region_reads-before.region_reads==1,"selective region read decodes exactly one bounded region")
 check(store.read_region(reference,Vector3i(0,4,0)).get("present",true)==false,"absent region is explicitly distinguished from a missing blob")
 check(not store.read_region(reference,Vector3i(-1,0,0)).get("ok",true),"invalid region coordinate rejected")
 before=store.stats();check(store.publish_snapshot(newer,reference,1).is_empty() and store.expand_snapshot(reference)==raw,"interrupted region publication cannot alter an existing checkpoint")
 var index_path:=path.path_join(reference.slice(8).hex_encode()+".tindex")
 var index:=FileAccess.get_file_as_bytes(index_path)
 var at:=40+int(index.decode_u32(24))*4+int(index.decode_u32(28))*8
 var blob_path:=path.path_join(index.slice(at+40,at+72).hex_encode()+".tpack")
 var blob:=FileAccess.get_file_as_bytes(blob_path);var broken:=blob.duplicate();broken[int(index.decode_u32(at+72)+index.decode_u32(at+76))-1]^=1;write(blob_path,broken)
 check(store.expand_snapshot(reference).is_empty() and not store.read_region(reference,coordinate).get("ok",true),"damaged referenced region fails instead of regenerating base terrain")
 check(store.publish_snapshot(raw,reference).is_empty(),"publisher refuses to overwrite a damaged immutable identity")
 write(blob_path,blob)
 var bad_index:=index.duplicate();bad_index.encode_u32(44,bad_index.decode_u32(40))
 var bad_id:=hash_bytes(bad_index);write(path.path_join(bad_id.hex_encode()+".tindex"),bad_index)
 var bad_ref:=reference.duplicate();for i in range(32):bad_ref[8+i]=bad_id[i]
 check(not store.describe_snapshot(bad_ref).get("ok",true),"valid digest cannot disguise duplicate page membership")
 broken=raw.duplicate();broken[40]^=1
 check(store.publish_snapshot(broken).is_empty(),"damaged native archive rejected before publication")
 store.close()
 check(store.open_store(path) and store.expand_snapshot(next)==newer,"fresh read-only store reopens exact checkpoint")
 check(store.publish_snapshot(raw).is_empty(),"read-only store cannot publish")
 store.close()
 var report:={"failures":failures,"checks":checks,"raw_bytes":raw.size(),"stored_first_bytes":first_stats.written_bytes,"initial_files":first_stats.written_files,"initial_publish_ms":publish_ms,"expand_ms":expand_ms,"changed_files":changed_files,"scope":"Native compressed region publication and selective reads; runtime terrain residency and whole-world frame cost are not qualified."}
 FileAccess.open("res://reports/terrain_region_store.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 # The directory was created by this test with a unique name; remove only its files.
 for file:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(file))
 DirAccess.remove_absolute(path)
 print("TERRAIN_REGION_STORE failures=",failures);quit(1 if failures else 0)
