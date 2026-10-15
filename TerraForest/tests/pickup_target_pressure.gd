# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var reach_calls:=0
var rows: Array=[]
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func reachable(_point: Vector3) -> bool:reach_calls+=1;return true
func _initialize() -> void:run.call_deferred()
func sample(pickups: Node3D,label: String,expected: bool,visits: int) -> void:
	var times: Array[int]=[];var max_visits:=0;var max_calls:=0;var stable:=true
	for warm in 20:pickups.aimed(Vector3.ZERO,Vector3(2,0,0),reachable)
	for iteration in 120:
		reach_calls=0
		var start:=Time.get_ticks_usec()
		var result: Dictionary=pickups.aimed(Vector3.ZERO,Vector3(2,0,0),reachable)
		times.append(Time.get_ticks_usec()-start)
		max_visits=maxi(max_visits,result.visited);max_calls=maxi(max_calls,reach_calls)
		stable=stable and result.ok==expected and result.queries<=pickups.ITEMS.size()
		await process_frame
	times.sort()
	var row: Dictionary={"label":label,"p50_us":times[60],"p95_us":times[114],"max_us":times[119],"max_candidates":max_visits,"max_occlusion_calls":max_calls,"catalog_types":pickups.ITEMS.size()}
	rows.append(row);print("PICKUP_TARGET_PRESSURE ",JSON.stringify(row))
	check(stable and max_visits==visits and max_calls<=1,label+" exact work bound and target outcome")
	check(times[114]<=500,label+" query p95 within 0.5 ms component budget")
func run() -> void:
	Engine.max_fps=60
	var pickups=preload("res://addons/world_runtime/material_pickups.gd").new();root.add_child(pickups)
	var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	if not pickups.prepare(persistence):quit(1);return
	pickups.stores[1].spawn(Vector3(1,0,0),Vector3.ZERO)
	await sample(pickups,"one_local",true,1)
	var count:=1
	for item: int in pickups.stores:
		var amount: int=4095 if item==1 else 4096
		count+=pickups.stores[item].spawn_grid(amount,Vector3(1000,0,1000),1,Vector3.ZERO).size()
	check(count==pickups.ITEMS.size()*4096,"every item store filled with distant population")
	await sample(pickups,"full_distant_population",true,1)
	# Move enough distant records into the ray's cell to exhaust the global budget.
	var store: RefCounted=pickups.stores[1]
	var distant: Dictionary=store.query_sphere(Vector3(1008,8,1008),32,4096,4096)
	check(distant.complete and distant.ids.size()>1024,"dense fixture source complete")
	for i in 1024:store.set_position(distant.ids[i],Vector3(1,0,0))
	await sample(pickups,"dense_local_rejected",false,1024)
	DirAccess.make_dir_recursive_absolute("res://reports/pickup_target_pressure")
	FileAccess.open("res://reports/pickup_target_pressure/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"population":count,"rows":rows,"scope":"Targeting CPU component only; stubbed winner occlusion, no rendering/thermal qualification"},"  "))
	pickups.free();print("PICKUP_TARGET_PRESSURE failures=",failures);quit(1 if failures else 0)
