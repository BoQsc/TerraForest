# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/world_runtime/world_runtime.gdextension")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(parent: Node,position: Vector3,size: Vector3) -> void:
	var body:=StaticBody3D.new();body.position=position
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider);parent.add_child(body)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	box(world,Vector3(0,-0.5,0),Vector3(30,1,30));box(world,Vector3(3,2,0),Vector3(1,4,10))
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(100010)
	store.spawn_grid(100000,Vector3(1000,0,1000),2,Vector3.ZERO)
	var id: int=store.spawn(Vector3(0,1,0),Vector3.ZERO)
	var actor: CharacterBody3D=ClassDB.instantiate("NativeEntityActor")
	var collider:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=0.35;shape.height=1.8;collider.shape=shape;actor.add_child(collider);world.add_child(actor)
	check(actor.bind_entity(store,id),"near-field proxy binds persistent store record")
	for i in 120:
		await physics_frame
		actor.tick(Vector3(10,1,0),1.0/60,true)
	check(actor.position.x>2.0 and actor.position.x<2.2 and actor.is_on_floor(),"entity walks on floor and stops against real wall")
	check(store.get_position(id)==actor.global_position and store.statistics().moving==0,"collision result returns to store without duplicate integration")
	var before: Vector3=actor.position
	for i in 10:
		await physics_frame
		actor.tick(Vector3(-10,1,0),1.0/60,false)
	check(actor.position==before and store.get_position(id)==before,"unready collision freezes proxy and authoritative position")
	check(not actor.tick(Vector3(NAN,0,0),1.0/60,true) and not actor.tick(Vector3.ZERO,1,true) and actor.position==before,"invalid target or timestep does not mutate")
	store.set_position(id,Vector3(-2,1,0));await physics_frame;actor.tick(Vector3(-2,1,0),1.0/60,true)
	check(absf(actor.position.x+2)<0.001,"external authority position correction reaches collision proxy")
	store.step(1.0/60)
	check(store.statistics().last_step_visited==0,"100000 distant stationary records require no kinematic iteration")
	store.despawn(id);before=actor.position
	check(not actor.tick(Vector3.ZERO,1.0/60,true) and actor.position==before,"despawned handle stops proxy movement")
	world.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/entity_actor.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
	quit(1 if failures else 0)
