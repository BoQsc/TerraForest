# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func reference(records:Dictionary,bounds:AABB)->Array:
	var result:Array=[]
	for key:Vector2i in records:
		if records[key].intersects(bounds):result.append(key)
	return result
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var index:RefCounted=ClassDB.instantiate("NativeOwnerBoundsIndex")
	var records:Dictionary={};var admitted:=true
	for z in range(31,-1,-1):
		for x in 32:
			var key:=Vector2i(x,z)
			var bounds:=AABB(Vector3(x*64-7,(x+z)%5,z*64-9),Vector3(82,24,86))
			records[key]=bounds;admitted=admitted and index.set_bounds(key,bounds)
	check(admitted and index.statistics().owners==1024,"all default-world owners enter the native bounds index")
	var random:=RandomNumberGenerator.new();random.seed=1703
	var parity:=true
	for i in 300:
		var bounds:=AABB(Vector3(random.randf_range(-64,2100),random.randf_range(-30,30),random.randf_range(-64,2100)),Vector3(random.randf_range(0,150),random.randf_range(0,32),random.randf_range(0,150)))
		parity=parity and Array(index.intersecting(bounds))==reference(records,bounds)
	check(parity,"random 3D queries retain exact affected owners and insertion order")
	var local:=AABB(Vector3(1000,2,1000),Vector3(2,2,2))
	check(Array(index.intersecting(local))==reference(records,local) and index.statistics().last_query_nodes<100,"small local edits prune the 1024-owner tree")
	var before:Array=index.all_owners()
	check(not index.set_bounds(Vector2i(40000,0),local) and not index.set_bounds(Vector2i(1,1),AABB(Vector3(NAN,0,0),Vector3.ONE)) and Array(index.all_owners())==before,"invalid admission cannot alias another owner or modify retained state")
	var first:Vector2i=before[0]
	check(index.set_bounds(first,local) and Array(index.all_owners())==before,"updating actual coverage retains the owner's original scheduling order")
	records[first]=local
	check(Array(index.intersecting(local))==reference(records,local),"coverage updates remove the prior box and expose the replacement")
	check(index.set_unbounded(first) and first in index.intersecting(AABB(Vector3(-999,0,-999),Vector3.ONE)),"unknown coverage remains conservative outside indexed boxes")
	check(index.set_inactive(first) and not first in index.all_owners(),"empty sample owners do not receive invalidations")
	check(index.set_bounds(first,local) and Array(index.all_owners())==before,"reactivating an empty owner preserves its earlier position")
	index.erase(first);records.erase(first);index.set_bounds(first,local);records[first]=local
	check(Array(index.all_owners())==records.keys(),"retired and newly admitted owners follow dictionary insertion semantics")
	if "--owner-bounds-native-only" not in OS.get_cmdline_user_args():check_adapters(index,records,random)
	index.clear()
	check(index.statistics().owners==0 and index.intersecting(local).is_empty(),"reset releases all derived owner coverage")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/owner_bounds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("OWNER_BOUNDS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func check_adapters(index:RefCounted,records:Dictionary,random:RandomNumberGenerator)->void:
	# Compare the actual runtime adapters with their retained scan fallback.
	var forest=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	var boulders=load("res://addons/world_ecosystem/boulder_horizon.gd").new()
	var boulder_index:RefCounted=ClassDB.instantiate("NativeOwnerBoundsIndex")
	for key:Vector2i in records:
		forest._samples[key]={"transforms":[Transform3D.IDENTITY],"exclusion_bounds":records[key]}
		boulders._samples[key]={"transforms":[Transform3D.IDENTITY]}
		boulder_index.set_bounds(key,AABB(Vector3(key.x*64,0,key.y*64),Vector3(64,1,64)).grow(8))
	var forest_parity:=true;var boulder_parity:=true
	for i in 80:
		var bounds:=AABB(Vector3(random.randf_range(-32,2070),random.randf_range(-2000,2000),random.randf_range(-32,2070)),Vector3(24,40,28)) if i>0 else AABB()
		forest._exclusion_index=null;forest._reconcile.clear();forest._structure_region_changed(bounds)
		var expected:Array=forest._reconcile.keys();forest._exclusion_index=index;forest._reconcile.clear();forest._structure_region_changed(bounds)
		forest_parity=forest_parity and forest._reconcile.keys()==expected
		boulders._exclusion_index=null;boulders._reconcile.clear();boulders._exclusion_changed(bounds)
		expected=boulders._reconcile.keys();boulders._exclusion_index=boulder_index;boulders._reconcile.clear();boulders._exclusion_changed(bounds)
		boulder_parity=boulder_parity and boulders._reconcile.keys()==expected
	check(forest_parity,"forest local/global invalidations match the original exact 3D scan")
	check(boulder_parity,"boulder local/global invalidations retain horizontal padding and order at every height")
	forest.free();boulders.free()
