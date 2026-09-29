extends SceneTree
var checks := 0
var failures := 0
var base := ""
var packet := PackedByteArray()
var updated := PackedByteArray()
var empty := PackedByteArray()
const MIB := 1024*1024

func _initialize() -> void:
	if not ClassDB.class_exists("NativeBlockRegionIO"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func folder(name: String) -> String:
	var path := base.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func wait_results(io: RefCounted,count: int) -> Array:
	var results: Array = []
	var deadline := Time.get_ticks_msec()+15000
	while results.size()<count and Time.get_ticks_msec()<deadline:
		results.append_array(io.poll(mini(64,count-results.size())))
		if results.size()<count: OS.delay_msec(1)
	return results

func wait_completed(io: RefCounted,count: int) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while io.stats().completed<count and Time.get_ticks_msec()<deadline: OS.delay_msec(1)
	return io.stats().completed==count

func open_io(name: String,limit: int=16,bytes: int=8*MIB) -> RefCounted:
	var io: RefCounted = ClassDB.instantiate("NativeBlockRegionIO")
	var ticket: int = io.start(folder(name),limit,bytes)
	var results := wait_results(io,1)
	check(ticket>0 and results.size()==1 and results[0].ticket==ticket and results[0].ok and results[0].operation=="open","asynchronous open owns store: "+name)
	return io

func run() -> void:
	base=ProjectSettings.globalize_path("res://reports/rio_%d_%d" % [OS.get_process_id(),Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(base)
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.set_cells(PackedInt32Array([1,0,0,1]))
	packet=world.capture_region(Vector3i.ZERO)
	world.set_cells(PackedInt32Array([1,0,0,2]))
	updated=world.capture_region(Vector3i.ZERO)
	world.free()
	check_limits()
	check_ordering()
	check_saturation()
	check_shutdown()
	check_failed_open()
	check_world_handshake()
	check_sustained()
	var file := FileAccess.open("res://reports/block_region_io.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native bounded queue, ordering, lifecycle and real filesystem correctness; no automatic world paging or long-run throughput claim."},"  "))
	file.close()
	quit(1 if failures else 0)

func check_limits() -> void:
	var io: RefCounted = ClassDB.instantiate("NativeBlockRegionIO")
	check(io.read_region(Vector3i.ZERO)==0 and io.list_regions()==0,"closed queue rejects submissions")
	check(io.start("user://relative",16,8*MIB)==0,"start rejects virtual paths without creating a worker")
	check(io.start(folder("limits"),0,8*MIB)==0 and io.start(folder("limits"),257,8*MIB)==0,"request capacity bounded to 1..256")
	check(io.start(folder("limits"),16,2*MIB-1)==0 and io.start(folder("limits"),16,256*MIB+1)==0,"payload reservation budget bounded to 2..256 MiB")
	check(io.stats().worker_starts==0,"invalid configuration starts no threads")
	io=open_io("limits")
	check(io.start(folder("other"),16,8*MIB)==0,"active queue cannot be rebound to another directory")
	check(io.publish_regions([],[])==0 and io.publish_regions([packet],[])==0 and io.publish_regions([4],[empty])==0,"malformed batch containers rejected before queuing")
	check(io.publish_regions([packet],[PackedByteArray([1])])==0 and io.remove_region(Vector3i.ZERO,empty)==0,"checksum lengths checked before admission")
	check(io.collect_garbage(0)==0 and io.collect_garbage(257)==0,"maintenance work requires a bounded inspection count")
	var huge := PackedByteArray()
	huge.resize(2*MIB+1)
	check(io.publish_regions([huge],[empty])==0,"oversized region payload rejected before queueing")
	var list: Array = []
	var expected: Array = []
	for i in range(65):
		list.append(packet)
		expected.append(empty)
	check(io.publish_regions(list,expected)==0,"batch packet count bounded to 64")
	io.join()

func check_ordering() -> void:
	var io := open_io("ordered")
	var competitor: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
	check(not competitor.open_store(folder("ordered")).ok,"background worker retains exclusive directory lease")
	var original := packet.duplicate()
	var inputs: Array = [original]
	var expected: Array = [empty]
	var tickets: Array = [io.publish_regions(inputs,expected)]
	original[0]^=1
	inputs[0]=PackedByteArray([1])
	expected[0]=PackedByteArray([2])
	inputs.clear()
	expected.clear()
	tickets.append(io.read_region(Vector3i.ZERO))
	tickets.append(io.publish_regions([updated],[empty]))
	tickets.append(io.publish_regions([updated],[packet.slice(packet.size()-32)]))
	tickets.append(io.read_region(Vector3i.ZERO))
	tickets.append(io.list_regions())
	var results := wait_results(io,6)
	check(results.size()==6,"every accepted operation retains one completion")
	if results.size()==6:
		var ordered := true
		for i in range(6): ordered=ordered and tickets[i]>0 and results[i].ticket==tickets[i]
		check(ordered,"completion tickets preserve FIFO order through an intervening failure")
		check(results[0].ok and results[1].ok and results[1].bytes==packet,"caller mutation cannot change an accepted packet or container")
		check(not results[2].ok and results[3].ok and results[4].bytes==updated,"worker validates stale versions and continues with the next valid write")
		check(results[5].ok and results[5].keys==PackedInt32Array([0,0,0]),"ordered index query returns committed signed region triples")
	check(io.stats().outstanding==0 and io.stats().reserved_bytes==0,"consuming completions releases all queue reservations")
	var invalid: int = io.publish_regions([PackedByteArray([1,2,3])],[empty])
	results=wait_results(io,1)
	check(invalid>0 and results.size()==1 and not results[0].ok,"semantic packet validation happens asynchronously on the worker")
	io.remove_region(Vector3i.ZERO,updated.slice(updated.size()-32))
	io.read_region(Vector3i.ZERO)
	io.collect_garbage(1)
	results=wait_results(io,3)
	check(results.size()==3 and results[0].ok and not results[1].ok and results[2].ok and results[2].inspected<=1,"ordered remove, missing read and bounded maintenance complete")
	io.request_stop()
	check(io.read_region(Vector3i.ZERO)==0,"stop immediately closes admission")
	io.join()
	check(not io.stats().running and competitor.open_store(folder("ordered")).ok,"joined worker releases its native store lease")
	competitor.close()

func check_saturation() -> void:
	var io := open_io("count",2,8*MIB)
	var a: int = io.list_regions()
	var b: int = io.list_regions()
	check(a>0 and b>a and io.list_regions()==0,"outstanding request count supplies immediate backpressure")
	check(wait_completed(io,2) and io.list_regions()==0,"unread completions still consume request capacity")
	check(io.poll(0).is_empty() and io.poll(65).is_empty() and io.stats().outstanding==2,"invalid poll limits cannot discard results")
	check(io.poll(1).size()==1 and io.list_regions()>b,"consuming one result admits one more request")
	io.join()
	check(io.stats().outstanding==2 and io.poll(64).size()==2,"shutdown preserves completed results for the consumer")
	io=open_io("bytes",16,2*MIB)
	var ticket: int = io.read_region(Vector3i.ZERO)
	check(ticket>0 and io.read_region(Vector3i.ZERO)==0 and io.list_regions()==0,"read reserves worst-case packet output before disk access")
	check(wait_completed(io,1) and io.read_region(Vector3i.ZERO)==0 and io.stats().reserved_bytes==2*MIB,"even failed unread results retain their reservation")
	io.poll(1)
	check(io.read_region(Vector3i.ZERO)>ticket,"polling releases byte capacity for the next read")
	io.join()
	io.poll(64)
	check(io.stats().high_bytes<=2*MIB and io.stats().high_requests<=16,"reported high-water marks stay within configured bounds")

func check_shutdown() -> void:
	var io := open_io("drain")
	var tickets: Array = [io.publish_regions([packet],[empty]),io.read_region(Vector3i.ZERO),io.list_regions()]
	io.request_stop()
	io.join()
	var results: Array = io.poll(64)
	check(results.size()==3 and results[0].ok and results[1].bytes==packet and results[2].ok,"shutdown drains accepted writes and reads before exiting")
	var previous: int = tickets[2]
	var ticket: int = io.start(folder("drain"),16,8*MIB)
	results=wait_results(io,1)
	check(ticket>previous and results.size()==1 and results[0].ok and results[0].keys==PackedInt32Array([0,0,0]),"restart preserves ticket identity and returns the persisted index")
	io.list_regions()
	io.join()
	check(io.start(folder("drain"),16,8*MIB)==0,"restart cannot discard unconsumed results")
	io.poll(64)
	for i in range(20):
		io=open_io("destroy%d" % i)
		io.publish_regions([packet],[empty])
		io=null # Destructor must join accepted write, without an explicit stop.
		var store: RefCounted = ClassDB.instantiate("NativeBlockRegionStore")
		var opened: Dictionary = store.open_store(folder("destroy%d" % i))
		check(opened.ok and store.read_region(Vector3i.ZERO).bytes==packet,"destruction drains writes and releases lease cycle %d" % i)
		store.close()

func check_failed_open() -> void:
	var io: RefCounted = ClassDB.instantiate("NativeBlockRegionIO")
	var ticket: int = io.start(base.path_join("does_not_exist"),16,8*MIB)
	var results := wait_results(io,1)
	io.join()
	check(ticket>0 and results.size()==1 and not results[0].ok and not io.stats().running,"filesystem open failure is reported and worker terminates")
	check(io.start(folder("retry"),16,8*MIB)>ticket,"failed opener can restart after consuming its result")
	results=wait_results(io,1)
	check(results.size()==1 and results[0].ok,"restart after open failure acquires a valid store")
	io.join()

func check_world_handshake() -> void:
	var io := open_io("handshake")
	var world: Node3D = ClassDB.instantiate("NativeBlockWorld")
	world.restore_region(packet,world.capture_region(Vector3i.ZERO))
	io.publish_regions([packet],[empty])
	world.set_cells(PackedInt32Array([1,0,0,2]))
	var results := wait_results(io,1)
	check(results.size()==1 and results[0].ok and not world.unload_region(packet) and world.get_cell(Vector3i(1,0,0))==2,"successful disk acknowledgement cannot evict a region edited after capture")
	io.publish_regions([updated],[packet.slice(packet.size()-32)])
	results=wait_results(io,1)
	check(results.size()==1 and results[0].ok and world.unload_region(updated) and not world.is_region_loaded(Vector3i.ZERO),"matching asynchronous acknowledgement permits native authored-region unload")
	io.read_region(Vector3i.ZERO)
	results=wait_results(io,1)
	check(results.size()==1 and results[0].ok and world.restore_region(results[0].bytes,empty) and world.capture_region(Vector3i.ZERO)==updated,"background read restores exact authored cells through the transfer API")
	world.free()
	io.join()

func check_sustained() -> void:
	var io := open_io("sustained",4,4*MIB)
	var previous := empty
	var ok := true
	for i in range(100):
		var bytes := packet if i%2==0 else updated
		var write_ticket: int = io.publish_regions([bytes],[previous])
		var read_ticket: int = io.read_region(Vector3i.ZERO)
		var results := wait_results(io,2)
		ok=ok and write_ticket>0 and read_ticket>write_ticket and results.size()==2
		if results.size()==2: ok=ok and results[0].ok and results[1].ok and results[1].bytes==bytes
		previous=bytes.slice(bytes.size()-32)
		ok=ok and io.stats().outstanding==0 and io.stats().reserved_bytes==0
	check(ok,"100 persisted revisions and dependent reads preserve bytes and release reservations")
	check(io.stats().worker_starts==1 and io.stats().finished==201 and io.stats().high_bytes<=4*MIB,"sustained I/O reuses one worker and stays within reservation budget")
	io.join()
