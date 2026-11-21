# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func check(passed:bool,label:String)->void:
	checks+=1
	if not passed:failures+=1
	print(("PASS " if passed else "FAIL ")+label)

func capture(core:RefCounted,origin:Vector3i,size:Vector3i)->PackedByteArray:
	var state:Dictionary=core.field_patch_state()
	return core.capture_field_patch(origin,size,state.revision,state.epoch)

func restore(core:RefCounted,patch:PackedByteArray)->Dictionary:
	var state:Dictionary=core.field_patch_state()
	return core.restore_field_patch(patch,state.revision,state.epoch)

func run()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"empty field initializes")
	var origin:=Vector3i(1274,58,1274);var size:=Vector3i(13,13,13)
	var baseline:=capture(core,origin,size)
	check(baseline.size()==48+13*13*13*3 and core.validate_field_patch(baseline),"bounded binary baseline validates")
	check(core.field_patch_state().revision==0,"baseline capture does not create an edit")
	var center:=Vector3(1280,64,1280)
	check(Codec.reply_ok(core.execute(Codec.brush(center,center,3,0,true,3))),"normal terrain edit succeeds")
	var edited:=capture(core,origin,size)
	check(edited!=baseline,"baseline differs from real player field edit")
	var outside:=Vector3(1266,64,1280)
	check(Codec.reply_ok(core.execute(Codec.brush(outside,outside,2,1,true,2))),"outside player edit succeeds")
	var outside_origin:=Vector3i(1263,61,1277);var outside_size:=Vector3i(6,6,6)
	var preserved:=capture(core,outside_origin,outside_size)
	var state:Dictionary=core.field_patch_state()
	check(not core.restore_field_patch(baseline,state.revision-1,state.epoch).ok,"stale mutation revision rejects")
	check(not core.restore_field_patch(baseline,state.revision,state.epoch-1).ok,"stale owner epoch rejects")
	check(core.capture_field_patch(origin,size,state.revision-1,state.epoch).is_empty(),"stale capture revision rejects")
	check(core.capture_field_patch(origin,size,state.revision,state.epoch-1).is_empty(),"stale capture epoch rejects")
	check(capture(core,origin,size)==edited,"rejected requests preserve current density and material")
	var old_key:Dictionary=core.geometry_cache_key(1264,1264,32,1)
	var old_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	check(Codec.reply_ok(old_mesh),"edited terrain populates native geometry cache")
	var response:=restore(core,baseline)
	check(response.ok and response.changes>0 and response.minimum==Vector3(origin) and response.maximum==Vector3(origin+size-Vector3i.ONE),"local restore gives exact changed sample bounds")
	check(capture(core,origin,size)==baseline,"restored baseline matches captured lattice bytes")
	check(capture(core,outside_origin,outside_size)==preserved,"outside authored edit remains unchanged")
	check(core.geometry_cache_key(1264,1264,32,1).key!=old_key.key,"derived geometry identity changes after field restoration")
	var restored_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	var reference_mesh:PackedByteArray=core.execute(Codec.command(1,[1264,1264,32,1]))
	check(Codec.reply_ok(restored_mesh) and Codec.reply_ok(reference_mesh) and restored_mesh.slice(12)==reference_mesh.slice(12) and restored_mesh!=old_mesh,"restored cached geometry matches fresh meshing and discards old surface")
	state=core.field_patch_state();response=restore(core,baseline)
	check(response.ok and response.changes==0 and core.field_patch_state()==state,"no-op restore does not dirty field")
	var corrupt:=edited.duplicate();corrupt[50]^=1
	check(not core.validate_field_patch(corrupt) and not restore(core,corrupt).ok,"damaged persistent baseline rejects")
	check(restore(core,edited).ok,"real edited samples can be restored too")
	var storage_path:=ProjectSettings.globalize_path("user://field_patch_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	check(store.open_store(storage_path,true),"isolated persistent region store opens")
	var raw:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
	var checkpoint:PackedByteArray=store.publish_snapshot(raw)
	check(checkpoint.size()==40,"real terrain checkpoint publishes")
	var mounted:RefCounted=ClassDB.instantiate("TerrainCore")
	check(mounted.mount_storage_checkpoint(storage_path,checkpoint,64),"fresh owner mounts deferred pages")
	check(capture(mounted,origin,size)==edited,"local capture resolves archived density and materials")
	check(restore(mounted,baseline).ok,"local reset operates on mounted storage")
	check(capture(mounted,outside_origin,outside_size)==preserved,"mounted reset preserves outside edits")
	var snapshot:RefCounted=mounted.capture_storage_snapshot()
	check(snapshot!=null and snapshot.stats().sample_bytes>0,"restored pages carry dirty storage versions")
	var next:PackedByteArray=store.publish_capture(snapshot,checkpoint)
	check(next.size()==40 and next!=checkpoint and mounted.commit_storage_snapshot(snapshot,next),"reset publishes and commits new durable checkpoint")
	var reopened:RefCounted=ClassDB.instantiate("TerrainCore")
	check(reopened.mount_storage_checkpoint(storage_path,next,64) and capture(reopened,origin,size)==baseline,"new checkpoint reopens exact reset state")
	check(capture(reopened,outside_origin,outside_size)==preserved,"fresh restore retains neighboring player changes")
	check(store.expand_snapshot(checkpoint)==raw,"original checkpoint remains immutable")
	state=core.field_patch_state()
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"same-seed reset accepted")
	check(core.field_patch_state().epoch!=state.epoch and not core.restore_field_patch(edited,0,state.epoch).ok,"same revision after reset cannot reuse old epoch")
	check(Codec.reply_ok(core.execute(Codec.command(6,[42,5]))) and not restore(core,edited).ok,"different seed cannot accept captured baseline")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,1]))) and not restore(core,edited).ok,"different generator cannot accept captured baseline")
	# Reconstruct a cut in a copied revision while the live authority advances.
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,31]))),"regional generator initializes for contact reconstruction")
	var point:=Vector3(1008,40,1008)
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,2,0,true,2))),"contact fixture has authored density and material")
	state=core.field_patch_state()
	var bounds:=Rect2i(992,992,32,32)
	var build_epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var frozen:RefCounted=core.capture_contact_core(bounds,state.revision,build_epoch)
	check(frozen!=null and core.capture_contact_core(bounds,state.revision+1,build_epoch)==null,"only a matching contact revision can be captured")
	# Compare the shared density-cell surface against independent extraction.
	var owner:=Codec.command(20,[992,992,32,1,build_epoch])
	var canonical:PackedByteArray=core.execute(Codec.command(1,[992,992,32,1,build_epoch]))
	var shared_mesh:PackedByteArray=frozen.execute(owner)
	check(Codec.reply_ok(shared_mesh) and shared_mesh.slice(12)==canonical.slice(12),"resident cells reproduce the rendered mesh and collision packet")
	for coord in [Vector3i(1008,40,1008),Vector3i(1004,36,1004),Vector3i(992,40,992)]:
		var contact:=Codec.command(43,[state.revision,build_epoch,coord.x,coord.y,coord.z])
		var actual:PackedByteArray=frozen.execute(contact)
		check(Codec.reply_ok(actual) and actual==core.execute(contact),"shared reconstruction reproduces water triangles, samples and solids at "+str(coord))
	# Seed a four-owner rim at a regional shoreline. Two outstanding edits
	# invalidate overlapping prisms on either side of the cell-owner seam.
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,9,0,true,2))),"author both sides of the resident seam before the local cuts")
	for x in [976,992,1008]:
		for z in [976,992,1008]:
			check(Codec.reply_ok(core.execute(Codec.command(44,[x,z,16,1,build_epoch]))),"resident triangle baseline populates")
	for brush_center in [Vector3(1007,40,1008),Vector3(1009,41,1007)]:
		var before:Dictionary=core.field_patch_state()
		var receipt:Dictionary=core.execute_edit_with_writes(Codec.brush(brush_center,brush_center,3,0,false,0))
		check(Codec.reply_ok(receipt.reply),"seam excavation accepted")
		var writes:PackedByteArray=receipt.get("writes",PackedByteArray())
		check(writes.size()>12 and writes.decode_u32(0)==1 and writes.decode_u32(4)==before.revision and writes.decode_u32(8)==receipt.reply.decode_u32(12),"seam repair receives actual writes for the committed revision")
	state=core.field_patch_state()
	var updated:RefCounted=core.capture_contact_core(bounds,state.revision,build_epoch)
	check(updated!=null,"changed triangle reader captures resident geometry")
	if updated!=null:
		for x in [992,1008]:
			for z in [992,1008]:
				var reference:PackedByteArray=core.execute(Codec.command(1,[x,z,16,1,build_epoch]))
				var repaired:PackedByteArray=updated.execute(Codec.command(20,[x,z,16,1,build_epoch]))
				check(Codec.reply_ok(repaired) and repaired.slice(12)==reference.slice(12),"replayed and reconstructed triangles match fresh render and collision")
		check(updated.execute(Codec.command(45)).decode_u64(12)>0,"unchanged terrain triangles reused after overlapping edits")
	frozen=core.capture_contact_core(bounds,state.revision,build_epoch)
	var packet:=Codec.command(42,[992,992,32])
	packet.append_array(PackedFloat32Array([point.x,point.y,point.z,32.0]).to_byte_array())
	packet.append_array(PackedInt32Array([1,992,992,1024,1024,state.revision,build_epoch]).to_byte_array())
	var prior:PackedByteArray=core.execute(packet)
	check(Codec.reply_ok(prior),"reference contact includes regional generator and authored samples")
	# Seed the outer rim before first authoring the pages intersected by the
	# large excavation. Page admission exposes the basal band outside the brush.
	for x in [944,960,976]:
		for z in [960,976,992]:
			check(Codec.reply_ok(core.execute(Codec.command(44,[x,z,16,1,build_epoch]))),"pre-edit rim is resident")
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,32,1,false,0))),"authority advances independently")
	state=core.field_patch_state()
	var rim:RefCounted=core.capture_contact_core(Rect2i(944,960,48,48),state.revision,build_epoch)
	check(rim!=null,"newly authored page rim fits the edit snapshot")
	if rim!=null:
		for z in [976,992]:
			var expected:PackedByteArray=core.execute(Codec.command(1,[960,z,16,1,build_epoch]))
			var actual:PackedByteArray=rim.execute(Codec.command(20,[960,z,16,1,build_epoch]))
			check(Codec.reply_ok(actual) and actual.slice(12)==expected.slice(12),"page admission preserves every sealed-floor triangle")
		check(rim.execute(Codec.command(45)).decode_u64(12)>0,"page admission replays unchanged faces while adding the sealed floor")
	var cut_reader:RefCounted=core.capture_contact_core(Rect2i(976,976,64,64),state.revision,build_epoch)
	check(cut_reader!=null,"full excavation fits a bounded edit reader")
	if cut_reader!=null:
		for x in [976,1008,1036]:
			for z in [976,1008,1036]:
				for y in [4,8,36,40]:
					var contact:=Codec.command(43,[state.revision,build_epoch,x,y,z])
					var local:PackedByteArray=cut_reader.execute(contact)
					check(Codec.reply_ok(local) and local==core.execute(contact),"full excavation cell index agrees with ordinary water contact at "+str(Vector3i(x,y,z)))
	check(not Codec.reply_ok(core.execute(packet)),"stale contact packet rejected on live authority")
	check(frozen!=null and frozen.execute(packet)==prior,"isolated contact produces byte-identical geometry after live edit")
	store.close()
	print("TERRAIN_FIELD_PATCH checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
