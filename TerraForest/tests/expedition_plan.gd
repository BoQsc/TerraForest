# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var world_seed:=1703
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--plan-seed="):world_seed=argument.trim_prefix("--plan-seed=").to_int()
	var options:Dictionary=preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS.duplicate()
	var worker:=Thread.new()
	worker.start(preload("res://addons/world_runtime/world_generation_plan.gd").build.bind(world_seed,preload("res://demo/world_launch.gd").terrain_generator(true,true),true,true,"user://generation_plans",options))
	while worker.is_alive():await process_frame
	var plan:Dictionary=worker.wait_to_finish()
	check(plan.get("ok",false),"default recipe fits terrain: "+str(plan.get("reason","")))
	if plan.get("ok",false):
		var anchor:=Vector3.INF
		for place:Dictionary in plan.navigation.places:
			if place.id==250:anchor=place.position
		check(anchor.is_finite(),"new default has resident trader")
		var coal:Dictionary={}
		for location:Dictionary in plan.get("exploration",{}).get("sites",[]):
			if location.id=="coal_mine":coal=location
		check(not coal.is_empty(),"new default includes real coal workings")
		if coal.is_empty():print("EXPLORATION_REJECTIONS ",plan.get("exploration",{}))
		var planner:RefCounted=ClassDB.instantiate("NativeRoadJourney")
		check(planner.configure(plan.navigation.roads,12).get("ok",false),"published road graph configures")
		if not coal.is_empty():
			var marker:Vector3=Vector3(coal.origin)+preload("res://addons/exploration/cave_layouts.gd").turn(Vector3(.5,0,-5.5),coal.rotation)
			check(coal.has("road_access"),"coal mine has a surveyed footpath from its vehicle stop")
			var outward:Dictionary=planner.route(anchor,coal.road_access.start,80)
			print("EXPEDITION_ROUTE ",{"anchor":anchor,"mine":marker,"stop":coal.road_access.start,"reason":outward.get("reason",""),"distance":outward.get("distance_m",0)})
			check(outward.get("ok",false),"trader has a connected road stop near mine")
			if outward.get("ok",false):
				var back:Dictionary=planner.route(outward.points[-1],outward.points[0],1,outward.points[-1]-outward.points[-2])
				check(back.get("ok",false),"mine stop has a forward drivable return route")
	print("EXPEDITION_PLAN checks=",checks," failures=",failures);quit(1 if failures else 0)
