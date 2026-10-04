# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var rows: Array=[]
	var passed:=true
	for population in [4096,100000,262144]:
		for crowded in [false,true]:
			var store=ClassDB.instantiate("NativeEntityStore")
			passed=store.configure(population) and passed
			var ids: PackedInt64Array=store.spawn_grid(population,Vector3.ZERO,.001 if crowded else 4.0,Vector3.ZERO)
			passed=ids.size()==population and passed
			for budget in [512,4096,16384]:
				var timings: Array[int]=[]
				var visited_max:=0
				var returned_max:=0
				var incomplete:=0
				var last: Dictionary={}
				for iteration in 36:
					var center:=Vector3.ZERO if crowded else Vector3(32+(iteration%3)*.125,0,32)
					var begin:=Time.get_ticks_usec()
					last=store.query_sphere_nearest(center,2.0 if crowded else 16.0,128,budget)
					var elapsed:=Time.get_ticks_usec()-begin
					if iteration>=4: timings.append(elapsed)
					visited_max=maxi(visited_max,last.visited);returned_max=maxi(returned_max,last.ids.size())
					if not last.selection_complete: incomplete+=1
					passed=passed and last.ok and last.visited<=budget and last.ids.size()<=128 and last.cells_visited<=4096
					if crowded and population>budget:
						passed=passed and not last.selection_complete and last.reason=="candidate_budget"
					elif crowded: passed=passed and last.selection_complete and last.visited==population
					else: passed=passed and last.selection_complete
				var total:=0
				for duration in timings: total+=duration
				timings.sort()
				rows.append({"population":population,"crowded":crowded,"candidate_budget":budget,"result_limit":128,"mean_us":float(total)/timings.size(),"p95_us":timings[ceili(timings.size()*.95)-1],"max_us":timings[-1],"visited_max":visited_max,"returned_max":returned_max,"incomplete_searches":incomplete,"queries":36})
			store=null
	var report: Dictionary={"passed":passed,"rows":rows,"scope":"Headless native spatial selection CPU timings, four warmup and 32 measured queries per case. Excludes renderer uploads, simulation, index creation, physics and GPU work. Crowded populations exceed search budgets and cannot guarantee global nearest results."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/entity_query_scaling.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ENTITY_QUERY_SCALING ",JSON.stringify(report))
	quit(0 if passed else 1)
