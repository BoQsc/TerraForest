# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var world: Node3D
var pool: Node3D
var store: RefCounted
var orders: RefCounted
var handle: int
var identity: int
var available:=true
var peak_work:=0
var peak_planning_us:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(point: Vector3,size: Vector3,layer: int=2) -> StaticBody3D:
	var body:=StaticBody3D.new();body.position=point;body.collision_layer=layer
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);world.add_child(body)
	return body
func tick() -> void:
	await physics_frame
	var result: Dictionary=pool.settle(1.0/Engine.physics_ticks_per_second,func(_bounds: AABB):return available)
	peak_work=maxi(peak_work,result.route_work);peak_planning_us=maxi(peak_planning_us,result.route_planning_us)
func until_state(wanted: Array,limit: int) -> String:
	for i in limit:
		await tick()
		var state: String=pool.navigation_status(handle).state
		if state in wanted:return state
	return pool.navigation_status(handle).state
func _initialize() -> void:run.call_deferred()
func run() -> void:
	world=Node3D.new();root.add_child(world)
	box(Vector3(0,-0.5,0),Vector3(12,1,12),1)
	store=ClassDB.instantiate("NativeEntityStore");store.configure(64)
	handle=store.spawn(Vector3(-3,0.93,0),Vector3.ZERO);identity=store.persistent_id(handle)
	orders=ClassDB.instantiate("NativeActorOrders");orders.configure(store);orders.set_target(identity,Vector3(3,0.93,0))
	pool=ClassDB.instantiate("NativeEntityActivation");world.add_child(pool);pool.configure(store,1);pool.set_orders(orders);pool.enable_navigation();pool.select(Vector3.ZERO,12,64)
	for i in 3:await physics_frame
	check(await until_state(["following"],120)=="following","native planner finds initial clear route")
	box(Vector3(0,1.5,0),Vector3(0.6,3,4))
	pool.invalidate_navigation(AABB(Vector3(-0.3,0,-2),Vector3(0.6,3,4)))
	check(pool.navigation_status(handle).state=="idle","intersecting edit invalidates disposable route")
	check(await until_state(["arrived"],480)=="arrived","actor replans and arrives around new wall")
	check(store.get_position(handle).distance_to(Vector3(3,0.9,0))<0.2,"arrival matches saved destination")
	pool.select(Vector3(100,0,0),1,64)
	check(pool.navigation_status(handle).state=="sleeping","leaving activation area discards active simulation")
	pool.select(Vector3.ZERO,12,64);orders.set_target(identity,Vector3(-3,0.93,0));await tick()
	check(pool.navigation_status(handle).state=="planning","return uses identity and starts a fresh route")
	available=false;var before: Vector3=store.get_position(handle)
	check(await until_state(["unavailable"],120)=="unavailable","unknown collision is reported separately from a blocked route")
	check(store.get_position(handle)==before,"unknown collision holds actual actor position")
	available=true;orders.set_target(identity,Vector3(100,0.93,0));await tick()
	check(pool.navigation_status(handle).state=="search_limit","distant target reports local search limit")
	var point: Vector3=store.get_position(handle)
	var gate:=box(Vector3(point.x-1.2,1.5,point.z),Vector3(0.3,3,2.7))
	box(Vector3(point.x+1.2,1.5,point.z),Vector3(0.3,3,2.7))
	box(Vector3(point.x,1.5,point.z-1.2),Vector3(2.7,3,0.3))
	box(Vector3(point.x,1.5,point.z+1.2),Vector3(2.7,3,0.3))
	orders.set_target(identity,Vector3(-3,0.93,0));pool.invalidate_navigation()
	check(await until_state(["blocked"],240)=="blocked","sealed enclosure terminates with blocked status")
	var old_expansions: int=pool.navigation_status(handle).expansions
	for i in 12:await tick()
	check(pool.navigation_status(handle).expansions==old_expansions,"blocked route does not restart every frame")
	gate.free();pool.invalidate_navigation()
	check(await until_state(["following"],240)=="following","opening enclosure permits route after invalidation")
	check(peak_work<=12,"shared planner never exceeds twelve work units per tick")
	check(pool.navigation_status(handle).nodes<=2048,"per-actor node storage remains capped")
	print("planning_peak_us=",peak_planning_us," work_peak=",peak_work," (cooperative 750us deadline, not a hard real-time guarantee)")
	world.free();await process_frame
	print("ACTOR_ROUTE_CONTRACT checks=",checks," failures=",failures);quit(1 if failures else 0)
