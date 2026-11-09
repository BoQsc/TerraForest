# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_store.gd"
func _initialize()->void:run.call_deferred()
func run()->void:
	var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
	var one:=packet(125000);var offset:=32+catalog.size()
	var source:=one.slice(0,offset)
	const COUNT:=1024
	source.encode_u32(12,COUNT);source.encode_u64(16,COUNT*125000);source.encode_u64(24,COUNT*12)
	for x in range(1,33):
		for z in range(1,33):
			var region:=one.slice(offset,offset+9076);region.encode_u64(0,(x<<24)|(9<<12)|z);source.append_array(region)
	var contacts:=PackedByteArray();contacts.resize(COUNT*12);contacts.fill(0);source.append_array(contacts)
	var water=ClassDB.instantiate("NativeRegionalWater")
	var samples:Array=[]
	for iteration in 8:
		check(water.restore_snapshot(source),"large immutable water fixture restores")
		var started:=Time.get_ticks_usec()
		var frozen:Variant=water.capture_storage_snapshot(catalog)
		var capture_us:=Time.get_ticks_usec()-started
		check(frozen is RefCounted,"capture returns a worker-owned snapshot")
		if not frozen is RefCounted:break
		var worker:=Thread.new();check(worker.start(frozen.serialize_snapshot)==OK,"serialization worker starts")
		started=Time.get_ticks_usec()
		var removed:int=water.brush(Vector3(4.25,36.25,4.25),.1,-1000)
		var edit_us:=Time.get_ticks_usec()-started
		water.invalidate_buildings(AABB(Vector3(8,36,8),Vector3(4,4,4)))
		while worker.is_alive():await process_frame
		var captured:PackedByteArray=worker.wait_to_finish()
		check(captured==source,"concurrent live amount and occupancy edits cannot mutate the frozen snapshot")
		check(removed==1000 and water.statistics().water_ml==COUNT*125000-1000,"snapshot retention preserves live mutation semantics")
		check(water.statistics().snapshot_pending_bytes<=128*1024*1024,"retained snapshot accounting stays within the existing bound")
		samples.append({"regions":COUNT,"capture_us":capture_us,"edit_us":edit_us,"pending_bytes":water.statistics().snapshot_pending_bytes})
		frozen=null;worker=null
	print("WATER_SNAPSHOT_COST ",JSON.stringify(samples))
	water=null;await process_frame
	print("WATER_SNAPSHOT_COST failures=",failures);quit(1 if failures else 0)
