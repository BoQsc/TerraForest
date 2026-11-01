# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func point(value:String)->Vector3:
	var parts:=value.trim_prefix("(").trim_suffix(")").split(",")
	return Vector3(float(parts[0]),float(parts[1]),float(parts[2])) if parts.size()==3 else Vector3.INF
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var path:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--plan="):path=argument.trim_prefix("--plan=")
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var roads:Array=[]
	for road:Dictionary in plan.roads:roads.append({"a":point(road.a),"b":point(road.b),"width":road.width})
	var start:=Vector3.INF;var towns:Array=[]
	for place:Dictionary in plan.places:
		if int(place.id)==250:start=point(place.position)
		if int(place.id)>=30 and int(place.id)<200:towns.append(place)
	var planner:RefCounted=ClassDB.instantiate("NativeRoadJourney")
	check(start.is_finite() and planner.configure(roads).get("ok",false),"production published road graph accepts the trader home")
	towns.sort_custom(func(a:Dictionary,b:Dictionary):return point(a.position).distance_to(start)<point(b.position).distance_to(start))
	var available:=0
	for place:Dictionary in towns.slice(1):
		var outward:Dictionary=planner.route(start,point(place.position),80)
		var back:Dictionary={}
		if outward.get("ok",false):back=planner.route(outward.points[-1],outward.points[0],1,outward.points[-1]-outward.points[-2])
		print("TOWN ",place.id," ",place.title," outward=",outward.get("distance_m",outward.get("reason",""))," return=",back.get("distance_m",back.get("reason","")))
		if outward.get("ok",false) and back.get("ok",false):available+=1
	check(available>0,"another town has a forward road journey and forward return")
	print("TRADER_ROAD_PLAN checks=",checks," failures=",failures);quit(1 if failures else 0)
