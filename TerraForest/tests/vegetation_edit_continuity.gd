# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var mutations:Array=[]
func measured(batch:Node,label:String,action:Callable)->bool:
	var uploaded:int=batch.render_stats().uploaded_transform_bytes
	var began:=Time.get_ticks_usec()
	var ok:bool=action.call()
	mutations.append({"operation":label,"scene_call_us":Time.get_ticks_usec()-began,"uploaded_payload_bytes":batch.render_stats().uploaded_transform_bytes-uploaded})
	return ok
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func rows(batch:Node)->Dictionary:
	var out:Dictionary={}
	for child in batch.get_children():
		if child is MultiMeshInstance3D and child.visible:
			for slot in child.multimesh.instance_count:
				var pose:Transform3D=child.multimesh.get_instance_transform(slot);pose.origin+=child.position
				out[roundi(pose.origin.x*32)+1]={"pose":pose,"fade":child.multimesh.get_instance_custom_data(slot)}
	return out
func steady(batch:Node,expected:Dictionary,label:String)->void:
	check(rows(batch)==expected,label+" preserves every visible survivor immediately")
	for frame in 4:
		await process_frame
		check(rows(batch)==expected,label+" has no missing/faded survivors on frame "+str(frame))
func _initialize()->void:run.call_deferred()
func run()->void:
	if DisplayServer.get_name()=="headless":print("FAIL render continuity requires GPU readback");quit(1);return
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	check(batch.configure_asset("edit/continuity",BoxMesh.new()) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,96,32,100000,1,8192),"strict production-size pages and one-page background budget")
	var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for i in 900:ids.append(i+1);poses.append(Transform3D(Basis.IDENTITY,Vector3(i/32.0,0,1)))
	check(batch.upsert_transforms(ids,poses),"dense vegetation group installed")
	for i in 12:await process_frame
	var expected:=rows(batch)
	check(expected.size()==900,"all initial pages resident")
	var removed:=PackedInt64Array([2,129,260,450,899])
	check(measured(batch,"bulk exclusion",func():return batch.remove_instances(removed)),"bulk exclusion removes several identities atomically")
	for id in removed:expected.erase(id)
	await steady(batch,expected,"bulk exclusion")
	var changed:=PackedInt64Array();var moved:Array[Transform3D]=[]
	for i in 80:
		var id:=500+i;var pose:Transform3D=expected[id].pose;pose.origin.y=.1
		changed.append(id);moved.append(pose);expected[id].pose=pose
	check(measured(batch,"support heights",func():return batch.upsert_transforms(changed,moved)),"terrain support update moves eighty existing plants")
	await steady(batch,expected,"support update")
	# A new owner member cannot republish the entire existing visible group.
	var additions:=PackedInt64Array();var added:Array[Transform3D]=[]
	for i in range(900,920):additions.append(i+1);added.append(Transform3D(Basis.IDENTITY,Vector3(i/32.0,0,1)))
	check(measured(batch,"insert",func():return batch.upsert_transforms(additions,added)),"new plants append to an existing group")
	var survivors_ok:=true
	for frame in 6:
		var visible:=rows(batch)
		for id in expected:survivors_ok=survivors_ok and visible.get(id)==expected[id]
		await process_frame
	check(survivors_ok and rows(batch).size()==915,"insert admission retains every old pose and fade while new plants stream")
	for frame in 12:await process_frame
	expected=rows(batch)
	# A terrain-height change can cross the 32 m spatial boundary.
	var migrated:Transform3D=expected[800].pose;migrated.origin.z+=32;expected[800].pose=migrated
	check(measured(batch,"cross group",func():return batch.upsert_transforms(PackedInt64Array([800]),[migrated])),"plant migrates into another spatial group")
	# The moved record is new residency in the destination; every unaffected record stays.
	var crossing_ok:=true
	for frame in 5:
		var visible:=rows(batch)
		for id in expected:
			if id!=800:crossing_ok=crossing_ok and visible.get(id)==expected[id]
		await process_frame
	check(crossing_ok and rows(batch)==expected,"cross-group migration preserves neighbours and original fade age")
	check(batch.render_stats().resident_transform_bytes<=100000,"resident payload stays inside configured ceiling")
	var snapshot:PackedByteArray=batch.capture_snapshot()
	var altered:Transform3D=expected[600].pose;altered.origin.y=2
	check(batch.upsert_transforms(PackedInt64Array([600]),[altered]) and batch.restore_snapshot(snapshot),"snapshot restore follows a same-identity transform change")
	for frame in 12:await process_frame
	check(rows(batch)==expected,"restore replaces GPU transforms as well as authoritative records")
	# Tight partial residency must never synchronously grow beyond its byte cap.
	check(batch.configure_render_streaming(true,96,1,8192,1,8192),"single-page resident ceiling")
	for i in 5:await process_frame
	var visible_before:=rows(batch)
	check(batch.remove_instances(PackedInt64Array([3,4,5])),"bulk removal with nonresident tail")
	var partial:=rows(batch);var retained:=true
	for id in visible_before:
		if not id in [3,4,5]:retained=retained and partial.get(id)==visible_before[id]
	check(retained and batch.render_stats().resident_transform_bytes<=8192,"partial residency preserves unaffected visible plants within the cap")
	check(batch.remove_instances(batch.get_ids()),"full collection removal")
	for i in 3:await process_frame
	check(rows(batch).is_empty() and batch.render_stats().resident_transform_bytes==0,"full removal leaves no stale rendered plants")
	check(batch.render_stats().pooled_empty_batches<=16 and batch.get_child_count()<=16,"empty vegetation page cache is bounded and retains no rendered instances")
	check(batch.upsert_transforms(PackedInt64Array([1]),[Transform3D(Basis.IDENTITY,Vector3(1,0,1))]),"removed vegetation pages can be reused")
	for frame in 3:await process_frame
	check(rows(batch).size()==1 and batch.render_stats().resident_instances==1,"page reuse admits exactly one fresh instance without stale slots")
	check(batch.clear_instances() and batch.get_child_count()==0,"explicit collection clear releases the empty page cache too")
	var folder:=ProjectSettings.globalize_path("res://reports")
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--vegetation-evidence-dir="):folder=argument.trim_prefix("--vegetation-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("vegetation_edit_continuity.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"mutations":mutations,"scope":"Finite scene-call timings exclude readback and do not measure GPU completion or sustained frame cost."},"  "))
	batch.free();await process_frame
	print("VEGETATION_EDIT_CONTINUITY checks=",checks," failures=",failures);quit(1 if failures else 0)
