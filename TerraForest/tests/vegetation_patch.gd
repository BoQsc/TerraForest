# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:=""
const BOUNDS=AABB(Vector3(100,10,100),Vector3(20,30,20))
const ROOTS=[12289,12290]

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--vegetation-patch-dir="):folder=argument.trim_prefix("--vegetation-patch-dir=")
	run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func ground()->RefCounted:
	var state:RefCounted=ClassDB.instantiate("NativeGroundCoverState")
	state.bind_world(1703,1)
	return state

func ground_capture(state:RefCounted,bounds:=BOUNDS,roots:=PackedInt64Array([12289,12290]))->PackedByteArray:
	var token:Dictionary=state.ground_patch_state()
	return state.capture_ground_patch(bounds,roots,token.revision,token.owner)

func ground_restore(state:RefCounted,data:PackedByteArray)->Dictionary:
	var token:Dictionary=state.ground_patch_state()
	return state.restore_ground_patch(data,token.revision,token.owner)

func tree_capture(state:RefCounted,roots:=PackedInt64Array([12289,12290]))->PackedByteArray:
	var token:Dictionary=state.harvest_patch_state()
	return state.capture_harvest_patch(roots,token.revision,token.owner)

func tree_restore(state:RefCounted,data:PackedByteArray)->Dictionary:
	var token:Dictionary=state.harvest_patch_state()
	return state.restore_harvest_patch(data,token.revision,token.owner)

func pose(point:=Vector3(110,20,110))->Transform3D:
	return Transform3D(Basis(Vector3.UP,.31).scaled(Vector3(.8,1.2,.9)),point)

func seal(data:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data.slice(0,data.size()-32))
	var output:=data.slice(0,data.size()-32);output.append_array(hash.finish());return output

func write(name:String,data:PackedByteArray)->void:
	var file:=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
	check(file!=null,"open isolated "+name)
	if file!=null:file.store_buffer(data);file.close()

func run()->void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	if "--reopen" in OS.get_cmdline_user_args():
		var plants:=ground();var trees:RefCounted=ClassDB.instantiate("NativeHarvestState")
		check(plants.restore_storage_snapshot(FileAccess.get_file_as_bytes(folder.path_join("ground-current.bin"))),"fresh-process current ground state")
		check(trees.restore_storage_snapshot(FileAccess.get_file_as_bytes(folder.path_join("tree-current.bin"))),"fresh-process current tree state")
		check(ground_restore(plants,FileAccess.get_file_as_bytes(folder.path_join("ground-patch.bin"))).ok,"fresh-process ground baseline restoration")
		check(tree_restore(trees,FileAccess.get_file_as_bytes(folder.path_join("tree-patch.bin"))).ok,"fresh-process tree baseline restoration")
		check(plants.capture_storage_snapshot()==FileAccess.get_file_as_bytes(folder.path_join("ground-expected.bin")),"fresh-process exact ground identity/transform and outside edits")
		check(trees.capture_storage_snapshot()==FileAccess.get_file_as_bytes(folder.path_join("tree-expected.bin")),"fresh-process exact selected tree flags and outside edits")
		finish();return
	var trees:RefCounted=ClassDB.instantiate("NativeHarvestState")
	check(trees.mark(ROOTS[0]) and trees.mark(999),"tree fixture exclusions")
	var tree_patch:=tree_capture(trees)
	check(tree_patch.size()==80 and trees.validate_harvest_patch(tree_patch),"bounded checksummed tree patch")
	check(tree_capture(trees,PackedInt64Array()).is_empty() and tree_capture(trees,PackedInt64Array([1,1])).is_empty(),"empty and duplicate tree selectors rejected")
	check(tree_capture(trees,PackedInt64Array([0])).is_empty(),"invalid tree identity rejected")
	var oversized:=PackedInt64Array();oversized.resize(4097)
	check(tree_capture(trees,oversized).is_empty(),"oversized tree selection rejected")
	var token:Dictionary=trees.harvest_patch_state()
	trees.unmark(ROOTS[0]);trees.mark(ROOTS[1]);trees.mark(1000)
	var tree_current:PackedByteArray=trees.capture_storage_snapshot()
	check(not trees.restore_harvest_patch(tree_patch,token.revision,token.owner).ok and trees.capture_storage_snapshot()==tree_current,"stale tree revision preserves every exclusion")
	token=trees.harvest_patch_state()
	check(not trees.restore_harvest_patch(tree_patch,token.revision,token.owner+1).ok,"foreign tree owner rejected")
	var bad:=tree_patch.duplicate();bad[bad.size()-1]^=1
	check(not trees.validate_harvest_patch(bad) and not tree_restore(trees,bad).ok and trees.capture_storage_snapshot()==tree_current,"tree corruption rejected atomically")
	for offset:int in [0,4,8,12,16,24,32,40]:
		bad=tree_patch.duplicate();bad.encode_s64(offset,-1)
		check(not trees.validate_harvest_patch(seal(bad)),"malformed tree field "+str(offset))
	var result:=tree_restore(trees,tree_patch)
	check(result.ok and result.changes==2 and trees.mask(PackedInt64Array([ROOTS[0],ROOTS[1],999,1000]))==PackedByteArray([1,0,1,1]),"tree restoration preserves unselected exclusions")
	token=trees.harvest_patch_state()
	check(tree_restore(trees,tree_patch).changes==0 and trees.harvest_patch_state()==token,"tree no-op retains revision")
	var tree_expected:PackedByteArray=trees.capture_storage_snapshot()
	trees.restore_storage_snapshot(tree_expected)
	check(not trees.restore_harvest_patch(tree_patch,token.revision,token.owner).ok,"full tree reload invalidates older token")
	var full:RefCounted=ClassDB.instantiate("NativeHarvestState")
	full.mark(500000);var capacity_patch:=tree_capture(full,PackedInt64Array([500000]));full.unmark(500000)
	for identity in range(1,262145):full.mark(identity)
	var full_before:PackedByteArray=full.capture_storage_snapshot()
	check(tree_restore(full,capacity_patch).get("reason")=="capacity" and full.capture_storage_snapshot()==full_before,"tree capacity failure preserves all exclusions")
	var state:=ground()
	check(state.mark(ROOTS[0]) and state.mark(1),"ground fixture removals")
	var plant:int=state.add(8,pose());var neighbor:int=state.add(2,pose(Vector3(99,20,110)))
	check(plant>0 and neighbor>0,"authored roots share an owner cell across patch boundary")
	var baseline_rows:Array=state.query(Vector2i(3,3))
	var patch:=ground_capture(state)
	check(patch.size()==192 and state.validate_ground_patch(patch),"bounded ground patch contains flags and exact authored transform")
	check(not ground_capture(state,BOUNDS,PackedInt64Array()).is_empty(),"authored-only patch supported")
	check(ground_capture(state,BOUNDS,PackedInt64Array([1])).is_empty(),"natural selector in unrelated cell rejected")
	check(ground_capture(state,BOUNDS,PackedInt64Array([ROOTS[0],ROOTS[0]])).is_empty(),"duplicate natural selector rejected")
	for bounds:AABB in [AABB(),AABB(Vector3.INF,Vector3.ONE),AABB(Vector3(100,10,100),Vector3(129,30,20)),AABB(Vector3(1990,10,100),Vector3(20,30,20))]:
		check(ground_capture(state,bounds).is_empty(),"invalid region rejected: "+str(bounds))
	var other:=ground();other.restore_storage_snapshot(state.capture_storage_snapshot())
	token=state.ground_patch_state()
	check(not other.restore_ground_patch(patch,other.ground_patch_state().revision,token.owner).ok,"foreign ground owner rejected")
	state.erase(plant);var replacement:int=state.add(3,pose(Vector3(108,20,110)))
	state.unmark(ROOTS[0]);state.mark(ROOTS[1]);state.mark(2)
	var current:PackedByteArray=state.capture_storage_snapshot()
	check(not state.restore_ground_patch(patch,token.revision,token.owner).ok and state.capture_storage_snapshot()==current,"stale ground token cannot mutate plants")
	bad=patch.duplicate();bad[bad.size()-1]^=1
	check(not ground_restore(state,bad).ok and state.capture_storage_snapshot()==current,"ground checksum failure is atomic")
	for offset:int in [0,4,8,16,48,52,56,64,72,80,88,96,104]:
		bad=patch.duplicate();bad.encode_s64(offset,-1)
		check(not state.validate_ground_patch(seal(bad)),"malformed ground field "+str(offset))
	for offset:int in [24,28,32,36,40,44,112,124,140,156]:
		bad=patch.duplicate();bad.encode_float(offset,NAN)
		check(not state.validate_ground_patch(seal(bad)),"nonfinite ground field "+str(offset))
	bad=patch.duplicate();bad.encode_s64(8,1704)
	check(not ground_restore(state,seal(bad)).ok and state.capture_storage_snapshot()==current,"different world seed rejected without mutation")
	result=ground_restore(state,patch)
	check(result.ok and result.changes==4,"ground restores two natural flags and replaces one planted root")
	check(state.query(Vector2i(3,3))==baseline_rows and state.mask(PackedInt64Array([1,2,ROOTS[0],ROOTS[1]]))==PackedByteArray([1,1,1,0]),"exact plants and neighboring removals preserved")
	check(state.capture_storage_snapshot().decode_s64(32)>replacement,"authored identity allocation never rewinds")
	token=state.ground_patch_state()
	check(ground_restore(state,patch).changes==0 and state.ground_patch_state()==token,"ground no-op retains revision")
	var expected:PackedByteArray=state.capture_storage_snapshot()
	state.restore_storage_snapshot(expected)
	check(not state.restore_ground_patch(patch,token.revision,token.owner).ok,"full ground reload invalidates older token")
	var empty:=ground();var empty_patch:=ground_capture(empty,BOUNDS,PackedInt64Array())
	check(empty_patch.size()==96,"empty baseline explicitly represents absence")
	empty.add(1,pose());empty.add(1,pose(Vector3(120,20,110)))
	check(ground_restore(empty,empty_patch).ok and empty.profile().placed==1,"empty baseline clears roots inside half-open region but not at upper boundary")
	var moved:=ground();moved.add(8,pose(Vector3(130,20,110)))
	var moved_before:PackedByteArray=moved.capture_storage_snapshot()
	check(not ground_restore(moved,patch).ok and moved.capture_storage_snapshot()==moved_before,"baseline identity moved outside region is not stolen")
	var packed:=ground()
	var reserved:int=packed.add(8,pose());packed.erase(reserved)
	for index in 256:packed.add(1,pose(Vector3(99,20,110)))
	var packed_before:PackedByteArray=packed.capture_storage_snapshot()
	check(ground_restore(packed,patch).get("reason")=="cell_capacity" and packed.capture_storage_snapshot()==packed_before,"cell capacity failure preserves roots and removals")
	var saturated:=ground()
	reserved=saturated.add(8,pose());saturated.erase(reserved)
	for index in 100000:
		var owner:int=index/256
		saturated.add(1,pose(Vector3(400+(owner%30)*32,20,400+(owner/30)*32)))
	var saturated_before:PackedByteArray=saturated.capture_storage_snapshot()
	check(saturated.profile().placed==100000,"global-capacity fixture admits all roots outside region")
	check(ground_restore(saturated,patch).get("reason")=="capacity" and saturated.capture_storage_snapshot()==saturated_before,"global capacity failure preserves all authored roots and removals")
	if not folder.is_empty():
		for pair:Array in [["tree-patch.bin",tree_patch],["tree-current.bin",tree_current],["tree-expected.bin",tree_expected],["ground-patch.bin",patch],["ground-current.bin",current],["ground-expected.bin",expected]]:write(pair[0],pair[1])
	large_patch()
	finish()

func large_patch()->void:
	var state:=ground();var roots:=PackedInt64Array()
	for row in range(4,8):
		for column in range(4,8):
			var owner:=row*63+column
			for index in 64:roots.append(1+owner*64+index)
			for index in 960:roots.append(1+63*63*64+owner*960+index)
	var bounds:=AABB(Vector3(128,0,128),Vector3(128,128,128))
	var started:=Time.get_ticks_usec();var baseline:=ground_capture(state,bounds,roots)
	var capture_us:=Time.get_ticks_usec()-started
	for identity:int in roots:state.mark(identity)
	started=Time.get_ticks_usec();var result:=ground_restore(state,baseline)
	var restore_us:=Time.get_ticks_usec()-started
	check(not baseline.is_empty() and result.ok and result.changes==roots.size() and state.profile().removed==0,"128m region restores 16384 selected natural roots")
	print("VEGETATION_PATCH_MAX bytes=",baseline.size()," capture_us=",capture_us," restore_us=",restore_us)

func finish()->void:
	print("VEGETATION_PATCH checks=",checks," failures=",failures)
	quit(1 if failures else 0)
