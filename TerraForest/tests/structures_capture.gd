# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/structures/structures.gdextension")
var checks:=0
var failures:=0
var blocks:Node3D
var models:Dictionary={}
var codec:RefCounted
var measurements:Array=[]
var checkpoint:=PackedByteArray()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func pose(x:float)->PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,65,0,0,1,0])
func legacy()->PackedByteArray:
	var full:bool=blocks.region_stats().whole_snapshot_available
	var encoded:Dictionary={}
	for id:String in models:
		var batch:Node3D=models[id]
		if batch.region_stats().unloaded_regions==0:encoded[id]=batch.capture_snapshot()
		else:
			full=false;var state:Dictionary=batch.capture_storage_state()
			encoded[id]=codec.encode_model_storage(state.resident,state.unavailable_keys,state.unavailable_checksums)
	if full:return codec.encode(blocks.capture_snapshot(),encoded)
	var state:Dictionary=blocks.capture_storage_state()
	return codec.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,encoded,checkpoint)
func freeze()->RefCounted:return codec.capture_save_snapshot(blocks,models,checkpoint)
func serialize_many(payload:RefCounted,expected:PackedByteArray)->Dictionary:
	var began:=Time.get_ticks_usec();var correct:=true
	for i in 4:correct=correct and payload.serialize_snapshot()==expected
	return {"correct":correct,"worker_us":Time.get_ticks_usec()-began}
func _initialize()->void:run.call_deferred()
func run()->void:
	codec=ClassDB.instantiate("NativeStructuresSnapshot");blocks=ClassDB.instantiate("NativeBlockWorld")
	for id:String in ["test/capture_a","test/capture_b"]:
		var batch:Node3D=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only()
		check(batch.configure_asset(id,BoxMesh.new()),"capture fixture asset configures")
		models[id]=batch
	check(codec.configure_assets(PackedStringArray(models.keys())),"capture schema seals")
	var cells:=PackedInt32Array()
	for i in 256:cells.append_array(PackedInt32Array([(i%16)*16,64,int(i/16)*16,1 if i%2 else 43]))
	check(blocks.set_cells(cells),"256 sparse chunks preserve material variants")
	var batch:Node3D=models["test/capture_a"]
	var ids:=PackedInt64Array();var poses:=PackedFloat32Array()
	for i in 1024:ids.append(i+1);poses.append_array(pose(float(i%20)))
	check(batch.upsert_instances(ids,poses),"1024 exact model identities populate fixture")
	var expected:=legacy();var equal:=true
	for mode:String in ["legacy","native","native","legacy"]:
		var began:=Time.get_ticks_usec();var bytes:=PackedByteArray();var payload:RefCounted
		if mode=="legacy":bytes=legacy()
		else:payload=freeze()
		var elapsed:=Time.get_ticks_usec()-began
		var row:Dictionary={"mode":mode,"main_us":elapsed,"bytes":expected.size()}
		if payload!=null:
			row.capture=payload.stats();var worker:=Thread.new();worker.start(serialize_many.bind(payload,expected))
			var result:Dictionary=worker.wait_to_finish();equal=equal and result.correct;row.worker_us=result.worker_us
		else:equal=equal and bytes==expected
		measurements.append(row)
	check(equal,"ABBA native captures serialize byte-identically through the existing codecs")
	var frozen:=freeze();var worker:=Thread.new();worker.start(serialize_many.bind(frozen,expected))
	for i in 24:
		blocks.set_cells(PackedInt32Array([0,64,0,2+i%2]));batch.upsert_instances(PackedInt64Array([1]),pose(80+i))
	var result:Dictionary=worker.wait_to_finish()
	check(result.correct and frozen.serialize_snapshot()==expected and legacy()!=expected,"concurrent live block/model edits cannot change frozen bytes")
	check(frozen.stats().serialized and frozen.stats().reserved_bytes==0,"serialization releases frozen buffers and their budget while retaining immutable bytes")
	var exposed:PackedByteArray=frozen.serialize_snapshot();exposed[0]^=1
	check(frozen.serialize_snapshot()==expected,"caller writes cannot corrupt the serialized cache")
	check(freeze().serialize_snapshot()==legacy(),"subsequent capture observes all live edits")
	frozen=null;worker=null
	var packet:PackedByteArray=blocks.capture_region(Vector3i(0,1,0))
	check(blocks.unload_region(packet),"block region becomes unavailable without discarding its identity")
	var model_packet:PackedByteArray=batch.capture_region(Vector3i(0,2,0))
	check(batch.unload_region(model_packet),"model region becomes unavailable with reserved identities")
	check(freeze().serialize_snapshot()==legacy(),"partial block/model capture retains exact unavailable digests")
	checkpoint.resize(32);checkpoint.fill(37)
	check(freeze().serialize_snapshot()==legacy(),"checkpoint-based storage envelope remains byte-identical")
	check(batch.begin_region_admission(model_packet),"partial model admission begins")
	var staged:Dictionary={}
	for i in 200:
		staged=batch.advance_region_admission(1,65536,500)
		if staged.staged_records>0:break
	check(staged.get("staged_records",0)==1 and freeze().serialize_snapshot()==legacy(),"save during admission keeps whole unavailable region instead of staged prefix")
	check(batch.upsert_instances(PackedInt64Array([5000]),pose(140)) and freeze().serialize_snapshot()==legacy(),"unrelated authored records coexist with hidden admission prefix")
	check(batch.cancel_region_admission(),"staged admission cancels")
	for i in 2000:
		if not batch.region_admission_stats().active:break
		batch.advance_region_admission(256,65536,500)
	check(not batch.region_admission_stats().active and freeze().serialize_snapshot()==legacy(),"rollback leaves captures equivalent")
	var other:=Thread.new();other.start(freeze)
	check(other.wait_to_finish()==null,"scene capture rejects off-main-thread access")
	check(codec.capture_save_snapshot(blocks,{},checkpoint)==null and codec.capture_save_snapshot(blocks,models,PackedByteArray([1]))==null,"incomplete registry and invalid checkpoint reject before capture")
	var empty:RefCounted=ClassDB.instantiate("NativeStructuresCapture")
	check(empty.serialize_snapshot().is_empty(),"uninitialized capture cannot authorize a save")
	var before:int=empty.stats().pending_bytes;var held:Array=[];var rejected:=false
	for i in 100:
		var item:=freeze()
		if item==null:rejected=true;break
		held.append(item)
	check(rejected and empty.stats().pending_bytes<=empty.stats().pending_limit_bytes,"simultaneous frozen payloads obey the 128 MiB pending bound")
	held.clear()
	check(empty.stats().pending_bytes==before,"releasing pending captures returns the full reservation")
	expected=legacy();frozen=freeze();blocks.free()
	for owner:Node3D in models.values():owner.free()
	models.clear();codec=null
	worker=Thread.new();worker.start(serialize_many.bind(frozen,expected))
	check(worker.wait_to_finish().correct,"worker serialization remains valid after every scene owner is freed")
	frozen=null;worker=null;other=null
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/structures_capture.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"  "))
	print("STRUCTURES_CAPTURE checks=",checks," failures=",failures);quit(1 if failures else 0)
