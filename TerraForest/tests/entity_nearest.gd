# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var store=ClassDB.instantiate("NativeEntityStore");store.configure(6000)
	var near: int=store.spawn(Vector3(1,0,0),Vector3.ZERO)
	for i in 100: store.spawn(Vector3(20+i*.01,0,0),Vector3.ZERO)
	var query: Dictionary=store.query_sphere_nearest(Vector3.ZERO,30,1,256)
	check(query.ids==PackedInt64Array([near]) and query.selection_complete and not query.complete and query.reason=="result_limit","near entity wins despite being last in cell traversal")
	query=store.query_sphere_nearest(Vector3.ZERO,30,1,2)
	check(not query.selection_complete and not query.complete and query.visited==2 and query.reason=="candidate_budget","budget exhaustion never claims globally nearest selection")
	var random:=RandomNumberGenerator.new();random.seed=1703
	var candidates: Array=[]
	for i in 5000:
		var position:=Vector3(random.randf_range(-100,100),random.randf_range(-100,100),random.randf_range(-100,100))
		store.spawn(position,Vector3.ZERO)
	# Build an independent oracle from all handles, including initial crowded cell.
	# The original query has a result cap; enumerate persistent identities instead.
	for identity in range(1,5102):
		var handle: int=store.resolve_identity(identity)
		var p: Vector3=store.get_position(handle)
		var d: float=float(p.x)*float(p.x)+float(p.y)*float(p.y)+float(p.z)*float(p.z)
		if d<=6400: candidates.append({"handle":handle,"distance":d,"identity":identity})
	candidates.sort_custom(func(a,b):return a.distance<b.distance or (a.distance==b.distance and a.identity<b.identity))
	query=store.query_sphere_nearest(Vector3.ZERO,80,128,16384)
	var exact: bool=query.ok and query.selection_complete and query.ids.size()==128
	for i in 128: exact=exact and query.ids[i]==candidates[i].handle
	check(exact,"nearest 128 match independent full-population distance oracle")
	check(query.visited<=5101 and query.cells_visited<=4096,"candidate and cell work remain bounded")
	check(store.query_sphere_nearest(Vector3(1000,0,0),1,8,32).complete,"empty region completes")
	check(not store.query_sphere_nearest(Vector3.INF,1,8,32).ok,"nonfinite center rejected")
	check(not store.query_sphere_nearest(Vector3.ZERO,1024,8,32).ok,"oversized cell footprint rejected")
	var ties=ClassDB.instantiate("NativeEntityStore");ties.configure(3)
	var first: int=ties.spawn(Vector3(1,0,0),Vector3.ZERO)
	var second: int=ties.spawn(Vector3(-1,0,0),Vector3.ZERO)
	check(ties.query_sphere_nearest(Vector3.ZERO,2,1,4).ids==PackedInt64Array([first]),"equal-distance ties favor persistent identity")
	ties.despawn(first)
	check(ties.query_sphere_nearest(Vector3.ZERO,2,1,4).ids==PackedInt64Array([second]),"deleted nearest handle is not retained")
	quit(0 if failures==0 else 1)
