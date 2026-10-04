# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var rows: Array=[]
	for population in [0,36864,262144,-262144]:
		var state=ClassDB.instantiate("NativeHarvestState")
		var wide: bool=population<0
		population=absi(population)
		for i in range(population): state.mark((1+((i*65537)%262144))*(17592186044417 if wide else 1))
		var begin:=Time.get_ticks_usec()
		var snapshot: PackedByteArray=state.capture_storage_snapshot()
		var cold_us:=Time.get_ticks_usec()-begin
		var timings: Array[int]=[]
		for sample in range(21):
			begin=Time.get_ticks_usec()
			var repeated: PackedByteArray=state.capture_storage_snapshot()
			timings.append(Time.get_ticks_usec()-begin)
			if repeated!=snapshot: quit(1);return
		timings.sort()
		var dirty_times: Array[int]=[]
		for sample in range(7):
			var id:=17592186044417 if wide else 1
			if population==0: state.mark(id);state.unmark(id)
			else: state.unmark(id);state.mark(id)
			begin=Time.get_ticks_usec()
			var dirty: PackedByteArray=state.capture_storage_snapshot()
			dirty_times.append(Time.get_ticks_usec()-begin)
			if dirty!=snapshot or not state.validate_snapshot(dirty): quit(1);return
		dirty_times.sort()
		var candidates:=PackedInt64Array()
		for i in range(36): candidates.append((1+i*6553)*(17592186044417 if wide else 1))
		begin=Time.get_ticks_usec()
		for sample in range(1000): state.mask(candidates)
		var mask_us: float=(Time.get_ticks_usec()-begin)/1000.0
		rows.append({"ids":population,"wide_ids":wide,"bytes":snapshot.size(),"first_capture_us":cold_us,"repeat_median_us":timings[10],"repeat_p95_us":timings[19],"dirty_median_us":dirty_times[3],"dirty_max_us":dirty_times[6],"owner_mask_mean_us":mask_us})
	print("HARVEST_CAPTURE_SCALING ",JSON.stringify(rows))
	quit()
