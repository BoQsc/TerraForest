# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var store=ClassDB.instantiate("NativeEntityStore");store.configure(4096)
	var a: int=store.spawn(Vector3(32.1,0,0),Vector3.ZERO)
	var b: int=store.spawn(Vector3(34,0,0),Vector3.ZERO)
	var from:=Vector3(31,0,0);var to:=Vector3(36,0,0)
	var hit: Dictionary=store.query_segment(from,to,0.32,32)
	check(hit.ok and hit.complete and hit.handle==a and absf(hit.fraction-0.156)<0.0001,"nearest sphere selected across spatial cell boundary")
	check(store.query_segment(to,from,0.32,32).handle==b,"reverse ray selects opposite nearest")
	check(store.query_segment(Vector3(32.1,0,0),to,0.32,32).fraction==0,"inside proxy begins at zero")
	check(store.query_segment(from+Vector3.UP,to+Vector3.UP,0.32,32).handle==0,"parallel miss")
	check(store.query_segment(from,Vector3(31.5,0,0),0.32,32).handle==0,"clipped endpoint cannot reach distant sphere")
	var tie: int=store.spawn(Vector3(32.1,0,0),Vector3.ZERO)
	check(store.query_segment(from,to,0.32,32).handle==a,"stable identity resolves equal-distance ties")
	store.despawn(a)
	check(store.query_segment(from,to,0.32,32).handle==tie,"removed identity cannot remain targeted")
	store.spawn_grid(100,Vector3(35,0,0),0.01,Vector3.ZERO)
	hit=store.query_segment(from,to,0.32,8)
	check(hit.ok and not hit.complete and hit.visited==8 and hit.handle==0,"budget exhaustion exposes no partial target")
	check(not store.query_segment(Vector3(NAN,0,0),to,0.32,32).ok and not store.query_segment(from,from,0.32,32).ok and not store.query_segment(Vector3.ZERO,Vector3(9,0,0),0.32,32).ok,"nonfinite degenerate and excessive reach rejected")
	var sparse=ClassDB.instantiate("NativeEntityStore");sparse.configure(4096)
	sparse.spawn_grid(3000,Vector3(1000,0,1000),1,Vector3.ZERO);sparse.spawn(Vector3(1,0,0),Vector3.ZERO)
	hit=sparse.query_segment(Vector3.ZERO,Vector3(2,0,0),0.32,8)
	check(hit.complete and hit.handle>0 and hit.visited==1,"distant population does not increase local candidate work")
	print("ENTITY_SEGMENT failures=",failures);quit(1 if failures else 0)
