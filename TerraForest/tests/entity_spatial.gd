# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func oracle(store: RefCounted,ids: PackedInt64Array,center: Vector3,radius: float) -> PackedInt64Array:
	var result:=PackedInt64Array()
	for id: int in ids:
		if store.contains(id) and store.get_position(id).distance_squared_to(center)<=radius*radius: result.append(id)
	result.sort();return result
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore")
	store.configure(4096)
	var ids: PackedInt64Array=store.spawn_grid(4096,Vector3(-256,-16,-256),8,Vector3.ZERO)
	for i in range(0,4096,7): store.set_velocity(ids[i],Vector3(400,-240,-500))
	check(store.step(0.1),"moving entities cross positive and negative cell boundaries")
	for i in 12:
		var center:=Vector3(-250+i*41,-25+i%3*7,-220+i*37)
		var query: Dictionary=store.query_sphere(center,35.0,4096,16384)
		var found: PackedInt64Array=query.ids;found.sort()
		check(query.ok and query.complete and found==oracle(store,ids,center,35),"indexed sphere agrees with exhaustive oracle %d" % i)
	var old: int=ids[0];var old_position: Vector3=store.get_position(old)
	store.despawn(old)
	var replacement: int=store.spawn(old_position,Vector3.ZERO)
	var exact: Dictionary=store.query_sphere(old_position,0.0)
	check(exact.complete and exact.ids.has(replacement) and not exact.ids.has(old),"slot reuse replaces generation-checked query handle")
	check(not store.query_sphere(Vector3.INF,1).ok and not store.query_sphere(Vector3.ZERO,NAN).ok,"nonfinite queries rejected")
	check(not store.query_sphere(Vector3.ZERO,1024).ok,"overlarge cell footprint rejected before traversal")
	check(not store.query_sphere(Vector3.ZERO,1,0).ok and not store.query_sphere(Vector3.ZERO,1,1,0).ok,"invalid output and work budgets rejected")
	var observations: Array=[]
	for population: int in [1024,100000]:
		store=ClassDB.instantiate("NativeEntityStore");store.configure(population)
		ids=store.spawn_grid(population,Vector3.ZERO,32,Vector3.ZERO)
		var start:=Time.get_ticks_usec()
		var query: Dictionary=store.query_sphere(Vector3(320,0,320),1.0)
		var micros:=Time.get_ticks_usec()-start
		check(query.ok and query.complete and query.ids.size()==1 and query.visited<=8,"local query visits at most eight candidates among %d entities" % population)
		observations.append({"population":population,"visited":query.visited,"cells":query.cells_visited,"query_us":micros})
	store=ClassDB.instantiate("NativeEntityStore");store.configure(10000)
	ids=store.spawn_grid(10000,Vector3.ZERO,0.001,Vector3.ZERO)
	var query: Dictionary=store.query_sphere(Vector3.ZERO,1.0,5,4096)
	check(query.ok and not query.complete and query.ids.size()==5 and query.reason=="result_limit","dense neighborhood reports result truncation")
	query=store.query_sphere(Vector3.ZERO,1.0,256,3)
	check(query.ok and not query.complete and query.visited==3 and query.reason=="candidate_budget","dense neighborhood obeys candidate budget and reports incomplete")
	for id: int in ids: store.despawn(id)
	check(store.statistics().spatial_cells==0 and store.query_sphere(Vector3.ZERO,1).ids.is_empty(),"despawn removes empty spatial cells")
	check(store.configure(8) and store.statistics().spatial_cells==0,"empty reconfiguration retains no spatial entries")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/entity_spatial.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"observations":observations,"scope":"native CPU spatial queries; no rendering, collision or networking"},"  "));file.close()
	print("SPATIAL_QUERY ",JSON.stringify(observations))
	quit(1 if failures else 0)
