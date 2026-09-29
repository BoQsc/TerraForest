extends SceneTree
const REGIONS := 64
const CHUNK_LIMIT := 512
var checks := 0
var failures := 0
var steps: Array[float] = []
var latency: Array[float] = []
var maximum_chunks := 0
var maximum_pending := 0
var bounded := true
var checkpoint := PackedByteArray()
var pager: RefCounted
var blocks: Node3D

func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func tick(focus: Vector3) -> void:
	bounded=pager.step(focus,checkpoint) and bounded
	var stats: Dictionary = pager.stats()
	steps.append(stats.last_ms)
	maximum_chunks=maxi(maximum_chunks,blocks.stats().chunks)
	maximum_pending=maxi(maximum_pending,stats.pending)
	bounded=bounded and stats.scan_last<=128 and stats.operation_last<=1 and maximum_chunks<=CHUNK_LIMIT and maximum_pending<=4
	await process_frame

func load_region(index: int) -> bool:
	var key := Vector3i(index,0,0)
	var focus := Vector3(index*64+32,32,32)
	var begin := Time.get_ticks_usec()
	var deadline := begin+10000000
	await tick(focus)
	while not blocks.is_region_loaded(key) and Time.get_ticks_usec()<deadline:
		await tick(focus)
	latency.append((Time.get_ticks_usec()-begin)/1000.0)
	return blocks.is_region_loaded(key)

func summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {}
	var sorted := samples.duplicate()
	sorted.sort()
	return {"samples":sorted.size(),"median":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max":sorted[-1]}

func run() -> void:
	Engine.max_fps=0
	var directory := ProjectSettings.globalize_path("res://reports/pager_stress_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	var path := directory.path_join("world.trw")
	DirAccess.make_dir_recursive_absolute(path+".regions")
	var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(store.open_store(path+".regions").ok,"stress fixture exclusively owns its new region store")
	blocks=ClassDB.instantiate("NativeBlockWorld")
	var empty: PackedByteArray = blocks.capture_snapshot()
	var hashes: Array[PackedByteArray] = []
	var authored := true
	var cells := 0
	for region in range(REGIONS):
		blocks.restore_snapshot(empty)
		var records := PackedInt32Array()
		# Repeated multi-storey building shells: floors, corner posts and roof ribs.
		# Each region has all 64 chunks, not just a one-cell occupancy sentinel.
		for cx in range(4):
			for cy in range(4):
				for cz in range(4):
					for x in range(16):
						for z in range(16):
							records.append_array(PackedInt32Array([region*64+cx*16+x,cy*16,cz*16+z,1+region%4]))
					for y in range(1,12):
						for corner in [Vector2i(0,0),Vector2i(15,0),Vector2i(0,15),Vector2i(15,15)]:
							records.append_array(PackedInt32Array([region*64+cx*16+corner.x,cy*16+y,cz*16+corner.y,2]))
					for z in range(16):
						records.append_array(PackedInt32Array([region*64+cx*16+8,cy*16+12,cz*16+z,3]))
		cells+=records.size()/4
		authored=blocks.set_cells(records) and authored
		var packet: PackedByteArray = blocks.capture_region(Vector3i(region,0,0))
		hashes.append(packet.slice(packet.size()-32))
		authored=store.publish_region(packet,PackedByteArray()).ok and authored
	check(authored and cells==1294336,"64 building-shell regions commit 4096 chunks and 1294336 authored cells")
	checkpoint=store.pin_checkpoint().checkpoint
	check(checkpoint.size()==32 and not store.read_block_checkpoint(checkpoint).ok,"fixture exceeds legacy whole-world resident reconstruction capacity")
	store.close()
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	codec.configure_assets(PackedStringArray())
	var raw: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(raw.encode({"terrain":PackedByteArray([1]),"structures":codec.encode_reference(checkpoint,{})}))
	file.close()
	var archive: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
	archive.configure(raw,codec,true)
	check(archive.acquire(path),"archive takes ownership after fixture publication")
	var state: Dictionary = codec.decode_storage(archive.decode(archive.read(path)).sections.structures)
	check(blocks.restore_storage_state(state.resident,state.unavailable_keys,state.unavailable_checksums) and blocks.stats().chunks==0,"large saved world starts with metadata and zero resident chunks")
	pager=ClassDB.instantiate("NativeBlockPager")
	check(pager.configure(blocks,archive,384,512,CHUNK_LIMIT),"stress pager starts with eight-region resident capacity")
	var exact := true
	var reached := true
	var arrivals := 0
	for pass_index in range(4):
		for offset in range(REGIONS):
			var index := offset if pass_index%2==0 else REGIONS-1-offset
			if not await load_region(index):
				reached=false
				print("UNREACHED ",index," ",pager.stats())
				break
			var packet: PackedByteArray = blocks.capture_region(Vector3i(index,0,0))
			exact=packet.slice(packet.size()-32)==hashes[index] and exact
			arrivals+=1
		# Exercise jumps that invalidate accepted read destinations.
		for index in [0,63,16,48,32,8,56,24]:
			await tick(Vector3(index*64+32,32,32))
	check(reached and latency.size()==REGIONS*4,"four complete traversals reach every destination under memory pressure")
	check(exact and arrivals==REGIONS*4,"all 256 arrivals reproduce exact authored region bytes")
	check(bounded and maximum_chunks==CHUNK_LIMIT,"every observed step respects scan transfer request and resident chunk bounds")
	check(pager.stats().failed_reads==0 and pager.stats().stale_results>0,"rapid direction changes discard stale reads without read failures")
	var focus := Vector3(32*64+32,32,32)
	for i in range(300): await tick(focus)
	var admissions: int = pager.stats().admitted
	var evictions: int = pager.stats().evicted
	for i in range(300): await tick(focus)
	check(admissions==pager.stats().admitted and evictions==pager.stats().evicted,"settled dense focus does not churn admission and eviction")
	state=blocks.capture_storage_state()
	check(archive.publish(path,archive.encode({"terrain":PackedByteArray([2]),"structures":codec.encode_storage(state.resident,state.unavailable_keys,state.unavailable_checksums,{},pager.get_checkpoint())}))==OK,"stress world saves exact unloaded references without full reconstruction")
	var final_stats: Dictionary = pager.stats()
	pager.stop()
	check(archive.region_read_stats().outstanding==0,"stress shutdown drains every owned disk request")
	archive.release()
	blocks.free()
	file=FileAccess.open("res://reports/block_pager_stress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"regions":REGIONS,"authored_chunks":REGIONS*64,"authored_cells":cells,"max_resident_chunks":maximum_chunks,"max_pending_reads":maximum_pending,"scene_step_ms":summary(steps),"arrival_latency_ms":summary(latency),"pager":final_stats,"scope":"Headless native cell storage and paging; no rendering, physics, terrain streaming or multiplayer. Teleport arrivals include already-resident destinations; not a high-speed vehicle benchmark."},"  "))
	file.close()
	quit(1 if failures else 0)
