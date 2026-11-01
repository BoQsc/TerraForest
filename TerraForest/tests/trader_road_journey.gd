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
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(50,10,0),Vector3(50,10,100))]).ok,"T intersection splits the actual street")
	var quote:Dictionary=route.route(Vector3(0,10,0),Vector3(50,10,100),1)
	check(quote.ok and is_equal_approx(quote.distance_m,150) and quote.fare==14,"fare uses connected road distance")
	check(quote.points==PackedVector3Array([Vector3(0,10,0),Vector3(50,10,0),Vector3(50,10,100)]),"route includes intersection")
	check(not route.route(Vector3(0,10,0),Vector3(250,10,100),20).ok,"distant place cannot snap across countryside")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(50,15,-50),Vector3(50,15,50))]).ok,"overpass data accepted")
	check(route.route(Vector3(0,10,0),Vector3(50,15,50),1).reason=="disconnected","crossing at another elevation is not a road junction")
	check(route.configure([road(Vector3(0,10,0),Vector3(100,10,0)),road(Vector3(100,10,0),Vector3(200,10,0),5)]).ok,"road graph excludes footpaths")
	check(not route.route(Vector3(0,10,0),Vector3(200,10,0),1).ok,"footpath cannot carry a paid ride")
	check(not route.configure([road(Vector3(NAN,0,0),Vector3.ZERO)]).ok,"invalid coordinates refused")
	check(not route.route(Vector3.ZERO,Vector3(100,0,0),1).ok,"failed configuration invalidates old graph")
	var loop:Array=[road(Vector3.ZERO,Vector3(0,0,40)),road(Vector3(0,0,40),Vector3(40,0,40)),road(Vector3(40,0,40),Vector3(40,0,0)),road(Vector3(40,0,0),Vector3.ZERO)]
	check(route.configure(loop).ok,"town block graph accepted")
	quote=route.route(Vector3(0,0,40),Vector3.ZERO,1,Vector3(0,0,1))
	check(quote.ok and quote.distance_m==120,"return follows forward around a block instead of reversing at the stop")
	check(quote.points[1]==Vector3(40,0,40),"return departure respects the car heading")
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
