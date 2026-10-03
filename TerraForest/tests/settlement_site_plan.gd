# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/structures/site_plan.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var source=load("res://addons/structures/prefabs/brick_cottage.tres")
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	check(asset.compose_frontage([source],64,8,3,1703),"maximum 128-cottage layout composes")
	for rotation in 4:
		var result: Dictionary=Plan.foundation(asset,Vector3i(900,0,900),rotation,48)
		check(result.ok,"rotated site plan accepted "+str(rotation))
		if not result.ok: continue
		var covered:=true
		for point in asset.foundation_samples(result.target,rotation,0):
			var found:=false
			for segment: Dictionary in result.segments:
				var a:=Vector2(segment.start.x,segment.start.z);var b:=Vector2(segment.finish.x,segment.finish.z)
				var p:=Vector2(point.x,point.z)
				var nearest:=a+(b-a)*clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)
				if nearest.distance_to(p)<=segment.half_width+0.001: found=true;break
			if not found: covered=false;break
		check(covered,"every native foundation column lies inside a flat grading core "+str(rotation))
		var bounded: bool=result.segments.size()<=256
		for segment: Dictionary in result.segments:
			bounded=bounded and segment.start.distance_to(segment.finish)>=1 and segment.start.distance_to(segment.finish)<=128 and segment.half_width<=16 and result.bounds.encloses(segment.bounds)
		check(bounded,"all segments respect native road bounds and combined protection envelope "+str(rotation))
	check(not Plan.foundation(asset,Vector3i(1,0,1),0,48).ok,"expanded shoulders reject world boundary")
	check(not Plan.foundation(asset,Vector3i(900,0,900),0,239).ok,"ceiling clearance rejected")
	check(not Plan.foundation(asset,Vector3i(900,0,900),4,48).ok,"invalid rotation rejected")
	asset.configure(PackedInt32Array([0,3,0,1]))
	check(not Plan.foundation(asset,Vector3i(900,0,900),0,48).ok,"elevated local base cannot produce a floating foundation plan")
	asset.configure(PackedInt32Array([0,0,0,1,4095,0,4095,1]))
	var oversized: Dictionary=Plan.foundation(asset,Vector3i(900,0,900),0,48)
	check(not oversized.ok and "256" in oversized.reason,"oversized plan rejects before allocating segments")
	quit(1 if failures else 0)
