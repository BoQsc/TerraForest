# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var cell_notifications:=0
var world:Node3D
var blocks:Node3D
var collection:Node3D
func snapshot()->PackedByteArray:
	return var_to_bytes([blocks.capture_snapshot(),collection.capture_snapshot()])
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	if not ClassDB.class_exists("NativeBlockWorld"):GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	world=Node3D.new();root.add_child(world)
	blocks=ClassDB.instantiate("NativeBlockWorld");world.add_child(blocks)
	collection=ClassDB.instantiate("NativeStaticBatch");world.add_child(collection)
	var mesh:=BoxMesh.new();mesh.size=Vector3(1.2,.75,.8)
	check(collection.configure_asset("test/crate/v1",mesh) and collection.configure_render_streaming(true,384,128,4194304,2,262144),"native collection is registered")
	var models:Dictionary={"test/crate/v1":collection}
	blocks.cells_changed.connect(func(_bounds:AABB):cell_notifications+=1)
	blocks.configure_history(4096,8);blocks.set_cells(PackedInt32Array([1000,40,1000,1]))
	var block_bytes:PackedByteArray=blocks.capture_snapshot();var history:Dictionary=blocks.history_stats();cell_notifications=0
	var asset=ClassDB.instantiate("NativeBlockPrefab");asset.configure(PackedInt32Array())
	var place=ClassDB.instantiate("NativePrefabPlacement")
	check(not place.place(blocks,asset,Vector3i(200,40,200),0,models,[]).ok,"fully empty prefab still rejects")
	asset.configure_model_attachments([{"model":"test/crate/v1","transform":Transform3D(Basis.IDENTITY,Vector3(0,.375,0))}])
	asset.configure_attachment_envelope(AABB(Vector3(-1,-.1,-1),Vector3(2,2,2)))
	var probe_origin:=Vector3i(200,40,200)
	var probes:Dictionary=place.ground_model_samples(asset,probe_origin,0,models)
	check(probes.ok and probes.support.size()==12 and probes.clearance.size()==36,"native grounded-model probes derive from actual mesh bounds")
	var shallow:Dictionary=place.ground_model_samples(asset,probe_origin,0,models,.02)
	check(shallow.ok and shallow.clearance==probes.clearance and shallow.support[0].is_equal_approx(probes.support[0]+Vector3(0,.23,0)),"thin block-floor support depth changes only the support plane")
	check(not place.ground_model_samples(asset,probe_origin,0,models,NAN).ok and not place.ground_model_samples(asset,probe_origin,0,models,0.).ok and not place.ground_model_samples(asset,probe_origin,0,models,2.).ok,"invalid support depth rejects before sampling")
	check(not place.ground_model_samples(asset,probe_origin,0,{}).ok and not place.ground_model_samples(asset,probe_origin,4,models).ok,"ground survey rejects missing model and invalid rotation")
	for turn in 4:
		var origin:=Vector3i(200+turn*10,40,200)
		var placed:Dictionary=place.place(blocks,asset,origin,turn,models,[])
		check(placed.ok,"model-only transaction in rotation "+str(turn)+": "+str(placed))
		check(placed.placements["test/crate/v1"].size()==1 and collection.get_instance(placed.placements["test/crate/v1"][0]).size()==12,"atomic placement returns its exact model identity")
		var rotated:Dictionary=place.ground_model_samples(asset,probe_origin,turn,models)
		var expected:=PackedVector3Array()
		for point:Vector3 in probes.support:
			var local:=point-Vector3(probe_origin)
			for quarter in turn:local=Vector3(1-local.z,local.y,local.x)
			expected.append(Vector3(probe_origin)+local)
		var matches:bool=rotated.ok and rotated.support.size()==expected.size()
		for point:Vector3 in expected:
			var found:=false
			for actual:Vector3 in rotated.support:found=found or actual.is_equal_approx(point)
			matches=matches and found
		check(matches,"ground probes follow the same quarter-turn as placed models")
	check(blocks.capture_snapshot()==block_bytes and blocks.history_stats()==history and cell_notifications==0,"model-only placement does not dirty block cells, invalidate terrain or erase block undo")
	check(collection.get_ids().size()==4,"all four model identities published")
	var saved:=snapshot()
	check(not place.place(blocks,asset,Vector3i(200,40,200),0,models,[]).ok and snapshot()==saved,"overlapping repeat rejects atomically")
	var bad=asset.duplicate();bad.configure_attachment_envelope(AABB(Vector3.ZERO,Vector3(.1,.1,.1)))
	check(not place.place(blocks,bad,Vector3i(300,40,200),0,models,[]).ok and snapshot()==saved,"model outside surveyed envelope rejects atomically")
	check(not place.place(blocks,asset,Vector3i(300,40,200),0,models,[AABB(Vector3(299,39,199),Vector3(3,3,3))]).ok and snapshot()==saved,"protected actor remains protected")
	blocks.set_edit_admission(func(_bounds:AABB):return false)
	check(not place.place(blocks,asset,Vector3i(300,40,200),0,models,[]).ok and snapshot()==saved,"world edit admission still gates model-only transactions")
	blocks.set_edit_admission(Callable())
	var restored:Array=bytes_to_var(saved)
	check(blocks.restore_snapshot(restored[0]) and collection.restore_snapshot(restored[1]) and snapshot()==saved,"model-only content restores exactly")
	world.free();print("PREFAB_MODEL_ONLY checks=",checks," failures=",failures);quit(1 if failures else 0)
