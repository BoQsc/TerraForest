# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	run.call_deferred()
func road(a:Vector3,b:Vector3,width:float=8)->Dictionary:return {"a":a,"b":b,"width":width}
func run()->void:
	var route:RefCounted=ClassDB.instantiate("NativeRoadJourney")
	var fitted:Array=[]
	for ends:Array in [[0.0,30.0],[30.0,31.5],[31.5,70.0]]:
		fitted.append({"start":Vector3(ends[0],0,0),"finish":Vector3(ends[1],0,0),"half_width":4.0,"grid_normalized":true})
	var published:=preload("res://addons/world_runtime/generated_region.gd").neighborhood_metadata({"ok":true,"center":Vector3.ZERO,"roads":fitted},1,"Split street","")
	check(route.configure(published.roads).ok and route.route(Vector3.ZERO,Vector3(70,0,0),1).get("ok",false),"short fitted junction sections remain connected in published navigation")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(50,10,0),Vector3(50,10,100))]).ok,"T intersection splits the actual street")
	var quote:Dictionary=route.route(Vector3(0,10,0),Vector3(50,10,100),1)
	check(quote.ok and is_equal_approx(quote.distance_m,150) and quote.fare==14,"fare uses connected road distance")
	check(quote.points==PackedVector3Array([Vector3(0,10,0),Vector3(50,10,0),Vector3(50,10,100)]),"route includes intersection")
	check(not route.route(Vector3(0,10,0),Vector3(250,10,100),20).ok,"distant place cannot snap across countryside")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(50,15,-50),Vector3(50,15,50))]).ok,"overpass data accepted")
	check(route.route(Vector3(0,10,0),Vector3(50,15,50),1).reason=="disconnected","crossing at another elevation is not a road junction")
	check(route.connected_stops(Vector3(0,10,0),1)==PackedVector3Array([Vector3(0,10,0),Vector3(100,10,0)]),"connected stops exclude the separated overpass")
	check(route.connected_stops(Vector3(NAN,0,0),1).is_empty(),"invalid starting point has no connected stops")
	check(route.configure([road(Vector3.ZERO,Vector3(120,0,0))],12).ok,"bounded intermediate road stops configure")
	check(route.get_stops().size()==11 and route.connected_stops(Vector3(60,0,0),1).size()==11,"mid-road stops share the whole physical road component")
	var surveyed:Dictionary=route.round_trip_stops(Vector3(60,0,0),1)
	check(surveyed.ok and surveyed.stops.is_empty(),"a straight dead-end component has no forward-only round-trip stops")
	check(route.route(Vector3(24,0,0),Vector3(96,0,0),1).ok,"expedition can stop along a long road")
	check(not route.configure([road(Vector3.ZERO,Vector3(120,0,0))],1).ok,"unbounded stop density is rejected")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(100,10,0),Vector3(200,10,0),4)]).ok,"road graph excludes footpaths")
	check(not route.route(Vector3(0,10,0),Vector3(200,10,0),1).ok,"footpath cannot carry a paid ride")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(99.5,10,0),Vector3(99.5,10,100),5)]).ok,"five-metre town approach is a vehicle road")
	check(route.route(Vector3(0,10,0),Vector3(99.5,10,100),1).ok,"half-cell frontage joins overlapping street surfaces")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(99.5,11,0),Vector3(99.5,11,100),5)]).ok and not route.route(Vector3(0,10,0),Vector3(99.5,11,100),1).ok,"frontage tolerance never joins different levels")
	check(not route.configure([road(Vector3(NAN,0,0),Vector3.ZERO)]).ok,"invalid coordinates refused")
	check(not route.route(Vector3.ZERO,Vector3(100,0,0),1).ok,"failed configuration invalidates old graph")
	var loop:Array=[road(Vector3.ZERO,Vector3(0,0,40)),road(Vector3(0,0,40),Vector3(40,0,40)),road(Vector3(40,0,40),Vector3(40,0,0)),road(Vector3(40,0,0),Vector3.ZERO)]
	check(route.configure(loop).ok,"town block graph accepted")
	quote=route.route(Vector3(0,0,40),Vector3.ZERO,1,Vector3(0,0,1))
	check(quote.ok and quote.distance_m==120,"return follows forward around a block instead of reversing at the stop")
	check(quote.points[1]==Vector3(40,0,40),"return departure respects the car heading")
	loop.append(road(Vector3.ZERO,Vector3(0,0,-60)))
	check(route.configure(loop,12).ok,"loop with a shared departure and return stem configures")
	surveyed=route.round_trip_stops(Vector3(0,0,-12),1)
	var eligible:PackedVector3Array=surveyed.get("stops",PackedVector3Array())
	check(not eligible.is_empty() and not eligible.has(Vector3(0,0,-60)),"mine survey excludes dead ends before fitting a site")
	var all_return:=true
	for stop:Vector3 in eligible:
		var out:Dictionary=route.route(Vector3(0,0,-12),stop,1)
		all_return=all_return and out.get("ok",false)
		if out.get("ok",false):all_return=all_return and route.route(out.points[-1],out.points[0],1,out.points[-1]-out.points[-2]).get("ok",false)
	check(all_return,"every admitted survey stop supports the same shortest outward route and forward return used in gameplay")
	quote=route.route(Vector3(0,0,-12),Vector3(0,0,-60),1,Vector3(0,0,1))
	check(quote.get("ok",false) and is_equal_approx(quote.get("distance_m",0),232),"forward return can revisit a junction from a different incoming edge")
	if quote.get("ok",false):
		var forward:=true
		for index in range(1,quote.points.size()-1):forward=forward and (quote.points[index]-quote.points[index-1]).normalized().dot((quote.points[index+1]-quote.points[index]).normalized())>=-.1
		check(forward,"loop return never inserts an illegal reversal")
	check(not route.route(Vector3.ZERO,Vector3(0,0,40),1,Vector3(NAN,0,0)).ok,"invalid departure heading refused")
	check(not route.configure([road(Vector3(1e20,0,0),Vector3.ZERO)]).ok,"unbounded coordinate cannot enter spatial index")
	check(not route.configure([road(Vector3.ZERO,Vector3(20,10,0))]).ok,"steep segments are outside the driver profile")
	check(route.follow(PackedVector3Array([Vector3.ZERO,Vector3(0,0,100)])),"road follower accepts route")
	var input:Dictionary=route.advance(Transform3D.IDENTITY,Vector3.ZERO,1.0/60,true,true)
	check(input.state=="following" and input.throttle>0 and is_zero_approx(input.steer),"straight trip supplies controls")
	input=route.advance(Transform3D.IDENTITY,Vector3(0,0,4),1.0/60,false,true)
	check(input.state=="unavailable" and input.hold and input.throttle==0,"unready collision stops controls")
	input=route.advance(Transform3D.IDENTITY,Vector3.ZERO,1.0/60,true,false)
	check(input.state=="blocked" and input.hold,"live obstruction stops controls")
	input=route.advance(Transform3D(Basis.IDENTITY,Vector3(5,0,10)),Vector3.ZERO,1.0/60,true,true)
	check(input.state=="blocked","off-road pose cannot be steered across unknown land")
	input=route.advance(Transform3D(Basis.IDENTITY,Vector3(0,0,99.5)),Vector3.ZERO,1.0/60,true,true)
	check(input.state=="arrived" and input.hold,"arrival requires stopped chassis at the road stop")
	check(route.follow(PackedVector3Array([Vector3.ZERO,Vector3(0,0,-100)])),"return path accepted")
	input=route.advance(Transform3D.IDENTITY,Vector3.ZERO,1.0/60,true,true)
	check(input.state=="blocked" and input.hold,"turn-around cannot teleport or reverse outside a validated maneuver")
	check(not route.follow(PackedVector3Array([Vector3.ZERO,Vector3.ZERO])),"zero-length control segment refused")
	check(route.follow(PackedVector3Array([Vector3.ZERO,Vector3(0,0,50),Vector3(50,0,50)])),"corner route accepted")
	input=route.advance(Transform3D(Basis(Vector3.UP,PI/3),Vector3(3,0,49)),Vector3(3,0,1),1.0/60,true,true)
	check(input.state=="following" and input.cursor==1,"corner handoff follows closest adjacent road segment")
	print("TRADER_ROAD_JOURNEY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
