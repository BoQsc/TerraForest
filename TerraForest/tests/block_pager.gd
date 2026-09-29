extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func until(pager: RefCounted,focus: Vector3,checkpoint: PackedByteArray,predicate: Callable) -> bool:
	var end := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<end:
		pager.step(focus,checkpoint)
		await process_frame
	return predicate.call()

func ticks(pager: RefCounted,focus: Vector3,checkpoint: PackedByteArray,count: int) -> void:
	for i in range(count):
		pager.step(focus,checkpoint)
		await process_frame

func fixture(path: String,records: PackedInt32Array) -> Dictionary:
	var c: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	c.configure_assets(PackedStringArray())
	var archive: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	archive.configure(ClassDB.instantiate("NativeWorldArchive"),c,true)
	archive.acquire(path)
	var w: Node3D = ClassDB.instantiate("NativeBlockWorld")
	w.set_cells(records)
	archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":c.encode(w.capture_snapshot(),{})}))
	var state: Dictionary = c.decode_storage(archive.decode(archive.read(path)).sections.structures)
	w.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums)
	return {"codec":c,"archive":archive,"world":w,"state":state,"path":path}

func save(f: Dictionary,pager: RefCounted) -> bool:
	var state: Dictionary = f.world.capture_storage_state()
	var bytes: PackedByteArray = f.codec.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,{},pager.get_checkpoint())
	return f.archive.publish(f.path,f.archive.encode({"terrain":PackedByteArray([2]),"structures":bytes}))==OK

func run() -> void:
	Engine.max_fps=240
	var directory := ProjectSettings.globalize_path("res://reports/pager_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var f := fixture(directory.path_join("world.trw"),PackedInt32Array([-1,0,0,1,0,0,0,2,768,0,0,3]))
	var w: Node3D = f.world
	var p: RefCounted = ClassDB.instantiate("NativeBlockPager")
	check(not p.configure(w,f.archive,32,128,128) and not p.configure(w,f.archive,64,80,128),"pager rejects unsupported radius and hysteresis configuration")
	check(not p.configure(w,f.archive,64,128,63) and p.configure(w,f.archive,64,128,128),"pager validates resident chunk bound and starts native read ownership")
	check(not p.configure(w,f.archive),"active pager rejects a second configuration")
	var near := Vector3(16,16,16)
	var far := Vector3(784,16,16)
	check(await until(p,near,f.state.checkpoint,func(): return w.is_region_loaded(Vector3i(0,0,0)) and w.is_region_loaded(Vector3i(-1,0,0))),"nearby positive and negative regions load automatically from metadata")
	check(w.get_cell(Vector3i(-1,0,0))==1 and w.get_cell(Vector3i(0,0,0))==2 and not w.is_region_loaded(Vector3i(12,0,0)),"pager admits exact nearby cells while distant region stays unloaded")
	check(p.stats().scan_high<=128 and p.stats().operation_high<=1,"native scan and region transfer work remain bounded per tick")
	w.configure_history(16384,16)
	w.set_cells(PackedInt32Array([0,0,0,4]))
	check(await until(p,far,f.state.checkpoint,func(): return w.is_region_loaded(Vector3i(12,0,0)) and not w.is_region_loaded(Vector3i(-1,0,0))),"travel loads a new region and evicts an unchanged committed distant region")
	check(w.get_cell(Vector3i(0,0,0))==4 and w.is_region_loaded(Vector3i(0,0,0)) and w.can_undo(),"distant unsaved edit and its undo survive unrelated paging")
	check(w.undo(AABB()) and w.get_cell(Vector3i(0,0,0))==2 and w.can_redo(),"undo remains usable after another region was admitted and evicted")
	check(save(f,p),"partially paged world publishes resident state and unavailable references together")
	await ticks(p,far,f.state.checkpoint,20)
	check(w.is_region_loaded(Vector3i(0,0,0)) and w.can_redo(),"saved region referenced by redo remains pinned")
	w.clear_history()
	check(await until(p,far,f.state.checkpoint,func(): return not w.is_region_loaded(Vector3i(0,0,0))),"clearing history permits clean distant eviction after successful publication")
	check(p.get_checkpoint().size()==32 and not f.archive.published_region_index().is_empty(),"pager consumes successful publication metadata without disk reads on the scene")
	w.configure_history(0,0)
	w.set_cells(PackedInt32Array([768,0,0,5]))
	check(await until(p,near,p.get_checkpoint(),func(): return w.is_region_loaded(Vector3i(0,0,0))),"return travel reloads previously evicted region")
	await ticks(p,near,p.get_checkpoint(),20)
	check(w.is_region_loaded(Vector3i(12,0,0)) and w.get_cell(Vector3i(768,0,0))==5,"dirty distant region stays resident even when undo recording is disabled")
	var revision: int = f.archive.published_region_index().revision
	var guard := FileAccess.open(f.path,FileAccess.READ)
	check(not save(f,p),"fixture forces world-root replacement failure")
	guard.close()
	check(f.archive.published_region_index(revision).is_empty(),"failed root replacement cannot advertise uncommitted region versions")
	await ticks(p,near,p.get_checkpoint(),10)
	check(w.is_region_loaded(Vector3i(12,0,0)),"pager does not evict dirty cells using a failed-save catalog")
	check(save(f,p),"retry commits edited distant region")
	check(await until(p,near,p.get_checkpoint(),func(): return not w.is_region_loaded(Vector3i(12,0,0))),"successful retry makes matching distant cells eligible for eviction")
	# Force accepted old-scene reads, then replace the native world before polling.
	w.restore_storage_state(f.state.resident,f.state.unavailable_keys,f.state.unavailable_checksums)
	p.step(near,f.state.checkpoint)
	var before: int = p.stats().epoch
	w.restore_storage_state(f.state.resident,f.state.unavailable_keys,f.state.unavailable_checksums)
	await ticks(p,near,f.state.checkpoint,40)
	check(p.stats().epoch>before and p.stats().stale_results>0,"whole-world restore advances pager epoch and discards accepted old-scene results")
	check(p.stats().operation_high<=1 and f.archive.region_read_stats().high_requests<=4,"reload keeps admission and request budgets bounded")
	p.stop()
	check(not p.stats().active and f.archive.region_read_stats().outstanding==0,"pager stop drains and consumes its owned read completions")
	f.archive.release()
	w.free()
	await dense_fixture(directory.path_join("dense.trw"))
	var file := FileAccess.open("res://reports/block_pager.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native automatic region selection, bounded admission, clean eviction, history protection and stale epoch rejection."},"  "))
	file.close()
	quit(1 if failures else 0)

func dense_fixture(path: String) -> void:
	var records := PackedInt32Array()
	for region in [0,4,8]:
		for x in range(4):
			for y in range(4):
				for z in range(4):
					records.append_array(PackedInt32Array([region*64+x*16,y*16,z*16,1]))
	var f := fixture(path,records)
	var w: Node3D = f.world
	var p: RefCounted = ClassDB.instantiate("NativeBlockPager")
	check(p.configure(w,f.archive,384,512,128),"dense fixture starts with a two-region resident budget")
	check(await until(p,Vector3(16,16,16),f.state.checkpoint,func(): return w.stats().chunks==128),"dense nearby regions fill but do not exceed configured resident capacity")
	var bounded := true
	for i in range(100):
		p.step(Vector3(528,16,16),f.state.checkpoint)
		bounded=bounded and w.stats().chunks<=128
		await process_frame
	check(bounded and w.is_region_loaded(Vector3i(8,0,0)) and not w.is_region_loaded(Vector3i(0,0,0)),"memory pressure trades farther committed regions for nearer requested regions")
	var admitted: int = p.stats().admitted
	var evicted: int = p.stats().evicted
	await ticks(p,Vector3(528,16,16),f.state.checkpoint,160)
	check(p.stats().admitted==admitted and p.stats().evicted==evicted,"stable focus does not thrash regions inside the loading radius at capacity")
	check(p.stats().scan_high<=128 and p.stats().operation_high<=1 and w.stats().chunks<=128,"dense travel respects scan transfer and cell residency bounds")
	check(save(f,p),"dense paged state remains saveable without loading all source chunks")
	p.stop()
	f.archive.release()
	w.free()
