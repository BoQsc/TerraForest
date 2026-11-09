# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var observations:Array[Dictionary]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func rows(batch:Node)->Dictionary:
	var result:Dictionary={}
	for child:Node in batch.get_children():
		if not child is MultiMeshInstance3D or not child.visible:continue
		var multi:MultiMesh=child.multimesh
		for index:int in multi.instance_count:
			var pose:Transform3D=multi.get_instance_transform(index);pose.origin+=child.position
			result[pose.origin]={"pose":pose,"fade":multi.get_instance_custom_data(index),"node":child.get_instance_id()}
	return result
func payload(rows_by_position:Dictionary)->Dictionary:
	var result:Dictionary={}
	for key:Vector3 in rows_by_position:result[key]={"pose":rows_by_position[key].pose,"fade":rows_by_position[key].fade}
	return result
func settled(batch:Node,expected:int)->void:
	for frame in 100:
		await process_frame
		var state:Dictionary=batch.render_stats()
		observations.append(state)
		if state.resident_instances==expected and state.pending_batches==0 and not state.selection_pending:return
	check(false,"render residency converges within bounded fixture frames")
func _initialize()->void:run.call_deferred()
func run()->void:
	if DisplayServer.get_name()=="headless":print("FAIL GPU readback is required");quit(2);return
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var scene:=Node3D.new();root.add_child(scene)
	var batch:Node3D=ClassDB.instantiate("NativeStaticBatch");scene.add_child(batch)
	var control:Node3D=ClassDB.instantiate("NativeStaticBatch");scene.add_child(control)
	var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
	check(batch.configure_asset("partition/fixture",mesh) and batch.configure_appearance_fade() and batch.configure_render_streaming(true,96,4,4096,1,128),"partitioned fixture retains strict logical-page, byte and upload limits")
	check(not batch.configure_render_partitions(3,.05) and batch.configure_render_partitions(2,.05),"only exact subdivisions of canonical 32 m owners are accepted")
	control.configure_asset("partition/fixture",mesh);control.configure_render_streaming(true,96,4,4096,1,128)
	var ids:=PackedInt64Array([1,2,3,4,5,6])
	var poses:Array[Transform3D]=[]
	for point:Vector3 in [Vector3(1,1,1),Vector3(2,1,1),Vector3(17,1,1),Vector3(18,1,1),Vector3(1,1,17),Vector3(-1,1,1)]:poses.append(Transform3D(Basis.IDENTITY,point))
	check(batch.upsert_transforms(ids,poses) and control.upsert_transforms(ids,poses),"same authoritative placements admitted in partitioned and ordinary collections")
	check(batch.capture_snapshot()==control.capture_snapshot() and batch.capture_region(Vector3i.ZERO)==control.capture_region(Vector3i.ZERO),"render partitioning leaves full snapshots and 32 m region packets byte identical")
	check(not batch.configure_render_partitions(4,.1),"partition policy cannot change after data admission")
	await settled(batch,6)
	var original:=rows(batch);var bounded:=true
	for state:Dictionary in observations:bounded=bounded and state.resident_batches+state.retired_batches<=state.batch_limit and state.retained_render_bytes<=state.byte_limit
	check(original.size()==6 and bounded and batch.region_stats().region_edge_m==32,"all six instances render within accounted budgets and canonical region ownership")
	check(batch.render_stats().partition_span_m==16.0 and batch.render_stats().logical_page_limit==4 and batch.render_stats().batch_limit==32,"draw-node ceiling explicitly reserves possible subdivisions without lowering logical admission")
	var encloses:=true
	for child:Node in batch.get_children():
		if not child is MultiMeshInstance3D or not child.visible or child.multimesh.instance_count==0:continue
		for index:int in child.multimesh.instance_count:
			var required:AABB=child.multimesh.get_instance_transform(index)*mesh.get_aabb().grow(.05)
			encloses=encloses and child.get_aabb().grow(.00001).encloses(required)
	check(encloses,"every draw AABB encloses transformed shader-displacement padding")
	batch.set_shadow_distance(1.0);batch.set_render_focus(Vector3.ZERO)
	await settled(batch,6)
	check(batch.render_stats().shadow_batches==batch.render_stats().resident_batches,"far subcells retain the accepted parent group's shadow policy")
	var snapshot:PackedByteArray=batch.capture_snapshot()
	var before:=payload(rows(batch));var expected:=before.duplicate(true)
	var moved:Dictionary=expected[poses[1].origin];expected.erase(poses[1].origin)
	poses[1].origin=Vector3(17,1,17);moved.pose=poses[1];expected[poses[1].origin]=moved
	check(batch.upsert_transforms(PackedInt64Array([2]),[poses[1]]) and payload(rows(batch))==expected,"cross-partition motion preserves every visible identity and fade age in the same scene call")
	await settled(batch,6)
	check(payload(rows(batch))==expected,"cross-partition coverage remains stable on subsequent frames")
	var unaffected:int=rows(batch)[Vector3(1,1,17)].node
	check(batch.remove_instances(PackedInt64Array([3])),"single removal accepted")
	expected.erase(Vector3(17,1,1))
	check(payload(rows(batch))==expected and rows(batch)[Vector3(1,1,17)].node==unaffected,"single removal leaves all survivors present and unrelated draw nodes intact")
	check(batch.remove_instances(PackedInt64Array([1,4])),"bulk removal accepted")
	expected.erase(Vector3(1,1,1));expected.erase(Vector3(18,1,1))
	check(payload(rows(batch))==expected,"bulk removal republishes only surviving visible records without restarting fades")
	check(batch.restore_snapshot(snapshot),"partitioned renderer restores the ordinary authoritative snapshot")
	await settled(batch,6)
	check(batch.capture_snapshot()==snapshot and rows(batch).size()==6,"snapshot restore rebuilds complete derived draw ranges")
	var packet:PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(batch.unload_region(packet) and batch.restore_region(packet),"unchanged canonical region unload/reload works with derived partitions")
	await settled(batch,6)
	check(batch.capture_snapshot()==snapshot and rows(batch).size()==6,"region reload preserves every saved identity and render record")
	check(batch.begin_transient_clear(),"partition layouts join bounded collection retirement")
	var cleared:=false
	for tick in 200:
		var state:Dictionary=batch.advance_transient_clear(2,500)
		if state.complete:cleared=true;break
	check(cleared and batch.render_stats().layout_pages==0 and batch.render_stats().layout_capacity_bytes==0 and batch.render_stats().retained_render_bytes==0,"retirement releases all layouts, draw payload and native indices")
	var sparse:Node3D=ClassDB.instantiate("NativeStaticBatch");scene.add_child(sparse)
	sparse.configure_asset("partition/sparse",mesh);sparse.configure_appearance_fade();sparse.configure_render_streaming(true,96,2,128,1,128);sparse.configure_render_partitions(2,.05)
	var sparse_poses:Array[Transform3D]=[]
	for point:Vector3 in [Vector3(-1,1,1),Vector3(1,1,1),Vector3(2,1,1),Vector3(17,1,1)]:sparse_poses.append(Transform3D(Basis.IDENTITY,point))
	sparse.upsert_transforms(PackedInt64Array([100,101,102,103]),sparse_poses)
	await settled(sparse,2)
	var sparse_before:=payload(rows(sparse))
	check(sparse_before.has(Vector3(-1,1,1)) and sparse_before.has(Vector3(17,1,1)),"small tail page fills a remaining budget without admitting an oversized earlier page")
	var larger:=BoxMesh.new();larger.size=Vector3(2,2,2)
	check(sparse.configure_asset("partition/sparse",larger) and payload(rows(sparse))==sparse_before,"asset-bound refresh cannot reorder a partial resident layout behind its GPU slots")
	var expanded:=true
	for child:Node in sparse.get_children():
		if not child is MultiMeshInstance3D or not child.visible:continue
		for index:int in child.multimesh.instance_count:
			expanded=expanded and child.get_aabb().grow(.00001).encloses(child.multimesh.get_instance_transform(index)*larger.get_aabb().grow(.05))
	check(expanded,"mesh replacement refreshes padded bounds of existing draw nodes")
	var held:Dictionary=sparse_before[Vector3(17,1,1)];sparse_before.erase(Vector3(17,1,1))
	var shifted:=Transform3D(Basis.IDENTITY,Vector3(1.5,1,1));held.pose=shifted;sparse_before[shifted.origin]=held
	sparse.upsert_transforms(PackedInt64Array([103]),[shifted])
	check(payload(rows(sparse))==sparse_before,"visible movement into a partially admitted bucket keeps exact coverage immediately")
	await settled(sparse,2)
	check(payload(rows(sparse))==sparse_before and sparse.render_stats().retained_render_bytes==128,"partial page remains visible when its pending growth cannot fit the remaining budget")
	check(sparse.set_instances(mesh,PackedFloat32Array([1,0,0,-2,0,1,0,1,0,0,1,1,1,0,0,18,0,1,0,1,0,0,1,1])),"full replacement can retire old identities before rebuilding padded bounds")
	await settled(sparse,2)
	check(rows(sparse).has(Vector3(-2,1,1)) and rows(sparse).has(Vector3(18,1,1)) and sparse.get_ids()==PackedInt64Array([1,2]),"full replacement publishes only the new authoritative identities")
	var folder:="res://reports/render_partitions";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"  "))
	scene.free();await process_frame;await process_frame
	print("RENDER_PARTITIONS checks=",checks," failures=",failures);quit(1 if failures else 0)
