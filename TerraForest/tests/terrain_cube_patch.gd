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
	var state:Dictionary=core.cube_patch_state()
	return core.capture_cube_patch(origin,size,state.revision,state.epoch)

func restore(core:RefCounted,patch:PackedByteArray)->Dictionary:
	var state:Dictionary=core.cube_patch_state()
	return core.restore_cube_patch(patch,state.revision,state.epoch)

func run()->void:
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"empty terrain initializes")
	var origin:=Vector3i(1279,63,1279);var size:=Vector3i(3,3,3)
	var baseline:=capture(core,origin,size)
	check(baseline.size()==75 and core.validate_cube_patch(baseline),"bounded all-air baseline validates")
	check(core.cube_patch_state().revision==0,"capture is read only")
	check(Codec.reply_ok(core.execute(Codec.command(3,[1279,63,1279,1]))) and Codec.reply_ok(core.execute(Codec.command(3,[1281,65,1281,3]))),"ordinary cube tool populates two columns")
	var edited:=capture(core,origin,size)
	check(edited!=baseline and edited[44]==1 and edited[70]==3,"captured cells match real terrain cube materials")
	check(Codec.reply_ok(core.execute(Codec.command(3,[1278,63,1279,2]))),"neighboring player cube added")
	var outside_origin:=Vector3i(1278,63,1279)
	var preserved:=capture(core,outside_origin,Vector3i.ONE)
	var state:Dictionary=core.cube_patch_state()
	var density:PackedByteArray=core.capture_field_patch(origin,size,state.revision,state.epoch)
	check(not core.restore_cube_patch(baseline,state.revision-1,state.epoch).ok,"stale revision rejects")
	check(not core.restore_cube_patch(baseline,state.revision,state.epoch-1).ok,"stale owner epoch rejects")
	check(core.capture_cube_patch(origin,size,state.revision-1,state.epoch).is_empty(),"stale capture revision rejects")
	check(core.capture_cube_patch(origin,size,state.revision,state.epoch-1).is_empty(),"stale capture epoch rejects")
	check(capture(core,origin,size)==edited,"rejection retains all cubes")
	var old_key:Dictionary=core.geometry_cache_key(1264,1264,32,1)
	var old_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	check(Codec.reply_ok(old_mesh),"edited cube geometry caches")
	check(core.experimental_snapshot_submit_brick(1264,1264,32,11,state.revision,48,80),"old worker snapshot admitted before cube restoration")
	var response:=restore(core,baseline)
	check(response.ok and response.changes==2 and response.minimum==Vector3(origin) and response.maximum==Vector3(origin+size),"restoration reports complete cube extent")
	check(capture(core,origin,size)==baseline,"air baseline removes inside cubes")
	check(capture(core,outside_origin,Vector3i.ONE)==preserved,"neighbor cube survives")
	var completed:Array=[];var deadline:=Time.get_ticks_msec()+5000
	while completed.is_empty() and Time.get_ticks_msec()<deadline:
		completed.append_array(core.experimental_snapshot_poll())
		if completed.is_empty():await process_frame
	check(completed.size()==1 and completed[0].stale and completed[0].status==2 and completed[0].positions.is_empty(),"pre-reset worker geometry cannot publish after cube changes")
	core.experimental_snapshot_stop()
	state=core.cube_patch_state()
	check(core.capture_field_patch(origin,size,state.revision,state.epoch)==density,"density field remains unchanged")
	check(core.geometry_cache_key(1264,1264,32,1).key!=old_key.key,"geometry identity includes exact cube restoration")
	var restored_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	var fresh_mesh:PackedByteArray=core.execute(Codec.command(1,[1264,1264,32,1]))
	check(Codec.reply_ok(restored_mesh) and Codec.reply_ok(fresh_mesh) and restored_mesh.slice(12)==fresh_mesh.slice(12) and restored_mesh!=old_mesh,"restored cached cube mesh equals fresh geometry")
	state=core.cube_patch_state();response=restore(core,baseline)
	check(response.ok and response.changes==0 and core.cube_patch_state()==state,"identical reset stays clean")
	var corrupt:=edited.duplicate();corrupt[44]^=1
	check(not core.validate_cube_patch(corrupt) and not restore(core,corrupt).ok,"corrupt baseline rejects")
	check(restore(core,edited).ok,"solid baseline restores destroyed cubes")
	var storage_path:=ProjectSettings.globalize_path("user://cube_patch_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	check(store.open_store(storage_path,true),"isolated region store opens")
	var raw:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
	var checkpoint:PackedByteArray=store.publish_snapshot(raw)
	check(checkpoint.size()==40,"cube world checkpoint publishes")
	var mounted:RefCounted=ClassDB.instantiate("TerrainCore")
	check(mounted.mount_storage_checkpoint(storage_path,checkpoint,64) and capture(mounted,origin,size)==edited,"fresh mount restores exact cubes")
	check(restore(mounted,baseline).ok,"cube reset works on mounted storage")
	var snapshot:RefCounted=mounted.capture_storage_snapshot()
	check(snapshot!=null and snapshot.stats().legacy_block_bytes==8,"snapshot contains surviving outside cube only")
	var next:PackedByteArray=store.publish_capture(snapshot,checkpoint)
	check(next.size()==40 and next!=checkpoint and mounted.commit_storage_snapshot(snapshot,next),"cube reset becomes durable")
	var reopened:RefCounted=ClassDB.instantiate("TerrainCore")
	check(reopened.mount_storage_checkpoint(storage_path,next,64) and capture(reopened,origin,size)==baseline,"fresh checkpoint reopens reset cells")
	check(capture(reopened,outside_origin,Vector3i.ONE)==preserved,"fresh restore preserves outside player cube")
	check(store.expand_snapshot(checkpoint)==raw,"original checkpoint stays immutable")
	state=core.cube_patch_state()
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))) and not core.restore_cube_patch(edited,0,state.epoch).ok,"world reset invalidates previous owner token")
	check(Codec.reply_ok(core.execute(Codec.command(6,[42,5]))) and not restore(core,edited).ok,"different seed rejects")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,1]))) and not restore(core,edited).ok,"different generator rejects")
	store.close()
	print("TERRAIN_CUBE_PATCH checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
