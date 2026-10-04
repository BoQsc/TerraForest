# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var rows: Array=[]
	for population in [0,36864,262144]:
		var state=ClassDB.instantiate("NativeHarvestState")
		for i in range(population): state.mark(1+((i*65537)%262144))
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
		rows.append({"ids":population,"bytes":snapshot.size(),"first_capture_us":cold_us,"repeat_median_us":timings[10],"repeat_p95_us":timings[19]})
	print("HARVEST_CAPTURE_SCALING ",JSON.stringify(rows))
	quit()
