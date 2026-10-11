# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(world: Node3D,point: Vector3,size: Vector3,layer: int) -> void:
	var body:=StaticBody3D.new();body.position=point;body.collision_layer=layer
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);world.add_child(body)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	box(world,Vector3(0,-0.5,0),Vector3(10,1,10),2)
	box(world,Vector3(0,1.5,0),Vector3(0.6,3,4),2)
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(16)
	var handle: int=store.spawn(Vector3(-1,1,0),Vector3.ZERO)
	var orders: RefCounted=ClassDB.instantiate("NativeActorOrders");orders.configure(store);orders.set_target(store.persistent_id(handle),Vector3(2,1,0))
	var pool: Node3D=ClassDB.instantiate("NativeEntityActivation");world.add_child(pool);pool.configure(store,1);pool.set_orders(orders);pool.select(Vector3.ZERO,10,16)
	for i in 120:
		await physics_frame
		pool.settle(1.0/Engine.physics_ticks_per_second,func(_bounds: AABB):return true)
	var point: Vector3=store.get_position(handle)
	check(point.x<-0.64 and point.x>-0.8,"active actor stops against authored-structure collision layer")
	check(point.y>0.88 and point.y<0.95,"authored-structure floor supports actor")
	var body: CharacterBody3D=pool.get_child(0)
	check(body.collision_layer==8 and body.collision_mask==3,"actors use separate membership and terrain/structure mask")
	pool.select(Vector3(100,0,0),1,16)
	check(body.collision_layer==0 and body.collision_mask==0,"sleeping proxy has no collision membership")
	pool.select(Vector3.ZERO,10,16)
	check(body.collision_layer==8 and body.collision_mask==3,"reactivation restores both world collision layers")
	var before: Vector3=store.get_position(handle)
	pool.settle(1.0/Engine.physics_ticks_per_second,func(_bounds: AABB):return false)
	check(store.get_position(handle)==before,"unavailable collision still holds actor")
	world.free();await process_frame;print("ACTOR_STRUCTURE_COLLISION failures=",failures);quit(1 if failures else 0)
