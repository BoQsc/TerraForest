# SPDX-License-Identifier: 0BSD
extends SceneTree
const Forest=preload("res://addons/vegetation/forest.gd")
var failures:=0
var checks:=0
var sun:=Vector3(-.35,.75,.55).normalized()
func check(okay:bool,label:String)->void:
	checks+=1
	if not okay:failures+=1;push_error(label)
func job()->RefCounted:return ClassDB.instantiate("NativeVegetationSelection")
func compare(forest:Node,label:String,origin:Vector3=Vector3.ZERO)->PackedByteArray:
	var legacy:=job();var packed:=job()
	check(packed.prepare_shadow_snapshot(forest.native_selection,origin,1024,256,sun),label+" snapshot accepted")
	var expected:PackedByteArray=legacy.shadow_mask(forest,origin,1024,256,sun)
	var actual:PackedByteArray=packed.build_shadow_mask()
	check(actual==expected and actual.size()==65536,label+" byte-exact mask")
	return actual
func _initialize()->void:
	var forest:=Forest.new()
	compare(forest,"empty")
	var ids:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for i in 48:
		ids.append(i+1);poses.append(Transform3D(Basis(Vector3.UP,i*.17).scaled(Vector3.ONE*(.5+(i%5)*.2)),Vector3(8+(i%8)*20,i%3,8+(i/8)*20)))
	check(forest.upsert_chunk("one",ids,poses),"initial membership")
	var original:=compare(forest,"initial")
	var revision:int=forest.canopy_revision
	check(forest.upsert_chunk("one",ids,poses) and forest.canopy_revision==revision,"unchanged membership keeps revision")
	compare(forest,"unchanged")
	forest.native_selection.clear();forest.native_selection.erase(1)
	check(compare(forest,"LOD certificate reset")==original,"LOD retirement retains distant canopy")
	forest.remove_root(19);compare(forest,"middle removal repairs moved slot")
	forest.remove_root(48);compare(forest,"tail removal")
	poses[18].origin+=Vector3(17,2,12)
	check(forest.upsert_chunk("one",ids,poses),"replacement and re-admission")
	compare(forest,"replacement")
	var snapshot:=job()
	check(snapshot.prepare_shadow_snapshot(forest.native_selection,Vector3.ZERO,1024,256,sun),"worker snapshot")
	var before:=compare(forest,"before concurrent edits")
	var worker:=Thread.new();check(worker.start(snapshot.build_shadow_mask)==OK,"worker starts")
	forest.remove_chunk("one")
	check(worker.wait_to_finish()==before,"worker input survives source mutation")
	compare(forest,"removed owner")
	check(forest.upsert_chunk("two",PackedInt64Array([7,8]),[Transform3D(Basis.IDENTITY,Vector3(200,0,200)),Transform3D(Basis.IDENTITY,Vector3(230,0,210))]),"new owner")
	before=compare(forest,"new owner")
	check(not forest.upsert_chunk("two",PackedInt64Array([7,7]),[Transform3D.IDENTITY,Transform3D.IDENTITY]),"reject duplicate update atomically")
	check(compare(forest,"after rejected update")==before,"rejected update retains pixels")
	forest.rebase(Vector3(16,0,32));compare(forest,"origin shift",Vector3(-16,0,-32))
	check(not snapshot.upsert_shadow_root(1,Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))),"reject nonfinite root")
	check(not snapshot.prepare_shadow_snapshot(forest.native_selection,Vector3.ZERO,1024,512,sun) and snapshot.build_shadow_mask().is_empty(),"retain resolution bound")
	check(not snapshot.prepare_shadow_snapshot(forest.native_selection,Vector3.ZERO,1024,256,Vector3.ZERO),"retain low-sun bound")
	forest.remove_chunk("two");ids.clear();poses.clear()
	for i in 16384:
		ids.append(i);poses.append(Transform3D(Basis.IDENTITY,Vector3((i%128)*8,0,(i/128)*8)))
	check(forest.upsert_chunk("large",ids,poses),"large forest")
	compare(forest,"16384 roots")
	var legacy:=job();var native:=job();var old_times:Array[int]=[];var new_times:Array[int]=[]
	for i in 7:
		var began:=Time.get_ticks_usec();legacy.prepare_shadow_mask(forest,Vector3.ZERO,1024,256,sun);old_times.append(Time.get_ticks_usec()-began)
		began=Time.get_ticks_usec();native.prepare_shadow_snapshot(forest.native_selection,Vector3.ZERO,1024,256,sun);new_times.append(Time.get_ticks_usec()-began)
	old_times.sort();new_times.sort()
	print("CANOPY_SNAPSHOT_TIMING roots=16384 dictionary_median_us=",old_times[3]," native_median_us=",new_times[3]," scope=preparation_only")
	var bounded:=job()
	for i in 65537:bounded.upsert_shadow_root(i,Transform3D.IDENTITY)
	check(not native.prepare_shadow_snapshot(bounded,Vector3.ZERO,1024,256,sun),"retain 65536-root snapshot bound")
	bounded.remove_shadow_root(65536)
	check(native.prepare_shadow_snapshot(bounded,Vector3.ZERO,1024,256,sun),"bound recovers after removal")
	forest.free()
	print("CANOPY_SHADOW_SNAPSHOT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
