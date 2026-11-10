# SPDX-License-Identifier: 0BSD
extends SceneTree
## Bounded selection benchmark; no saved world or generated assets.
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var scene:=Node3D.new();root.add_child(scene)
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch");scene.add_child(batch)
	var mesh:=BoxMesh.new()
	var ok:bool=batch.configure_asset("test/selection",mesh) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,1024,1024,7000000,64,65536) and batch.configure_render_partitions(2,0.05)
	var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for z in 16:
		for x in 16:
			for i in 64:
				ids.append(ids.size()+1)
				poses.append(Transform3D(Basis.IDENTITY,Vector3(x*32+(i%4)*8+1,(i/16)*8+1,z*32+((i/4)%4)*8+1)))
	ok=ok and batch.upsert_transforms(ids,poses)
	var snapshot:PackedByteArray=batch.capture_snapshot()
	for tick in 150:
		await process_frame
		if batch.render_stats().pending_batches==0 and not batch.render_stats().selection_pending:break
	var samples:Array[int]=[]
	for tick in 160:
		batch.set_render_focus(Vector3(240+(tick%2)*8,16,240))
		await process_frame
		samples.append(batch.render_frame_profile().selection_us)
	var state:Dictionary=batch.render_stats()
	samples.sort()
	ok=ok and samples[80]>0 and snapshot==batch.capture_snapshot() and state.resident_instances==ids.size() and state.budget_deferred==0 and state.retained_render_bytes<=state.byte_limit
	print("RENDER_SELECTION_COST ",JSON.stringify({"ok":ok,"median_us":samples[80],"p99_us":samples[158],"max_us":samples[159],"instances":ids.size(),"pages":state.resident_batches}))
	scene.free();await process_frame;await process_frame
	print("RENDER_SELECTION_COST failures=",0 if ok else 1);quit(0 if ok else 1)
