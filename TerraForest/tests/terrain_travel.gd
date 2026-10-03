# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var planner: RefCounted=ClassDB.instantiate("NativeTerrainPlanner")
	var focus:=Vector3(800,100,800)
	var base: Dictionary=planner.requests(focus,true,{},{},[])
	var idle: Dictionary=planner.requests_travel(focus,true,Vector3.ZERO,{},{},[])
	check(base.requests==idle.requests,"stationary planning unchanged")
	var ahead: Dictionary=planner.requests_travel(focus,true,Vector3(64,0,0),{},{},[])
	var preserves:=true
	for key in base.requested_keys:
		preserves=preserves and ahead.requested_keys.has(key)
	check(preserves,"current position loading retained")
	var corridor:=true
	for x in range(800,945,16): corridor=corridor and ahead.requested_keys.has(Vector3i(x,800,16))
	check(corridor,"continuous fine corridor across high-speed lookahead")
	var capped: Dictionary=planner.requests_travel(focus,true,Vector3(100000,0,0),{},{},[])
	check(ahead.requested_keys==capped.requested_keys,"extreme speed cannot expand past bounded horizon")
	var reverse: Dictionary=planner.requests_travel(focus,true,Vector3(-64,0,0),{},{},[])
	check(reverse.requested_keys.has(Vector3i(672,800,16)),"reverse travel preloads behind")
	var unique: Dictionary={}
	for key in ahead.requests: unique[key]=true
	check(unique.size()==ahead.requests.size(),"overlapping corridor samples do not duplicate jobs")
	check(not planner.requests_travel(focus,true,Vector3(INF,0,0),{},{},[]).ok,"nonfinite travel rejected")
	var stream=load("res://addons/volumetric_terrain/terrain_stream.gd").new()
	stream.planner=planner;stream.focus=focus;stream.travel_velocity=Vector3(64,0,0)
	check(stream._plan_requests()==ahead.requests,"stream scheduler consumes travel velocity")
	stream.free()
	quit(0 if failures==0 else 1)
