# SPDX-License-Identifier: 0BSD
extends Node3D
# Persistent ownership is always registered, independently of simulation activation.
var store: RefCounted
var pool: Node3D
var renderer: MultiMeshInstance3D
var status: Dictionary={}
var simulation_status: Dictionary={}
var _selection_time:=0.0
var _render_time:=0.0
var _suspended:=true
func prepare(persistence: RefCounted) -> bool:
	if store!=null:return false
	if not ClassDB.class_exists("NativeEntityStore"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	store=ClassDB.instantiate("NativeEntityStore")
	if not store.configure(1024):return false
	return persistence.register_component("world_actors",store.capture_storage_snapshot,_restore,store,store.capture_storage_snapshot())
func enable(capacity: int=16) -> bool:
	if store==null or pool!=null or not is_inside_tree():return false
	pool=ClassDB.instantiate("NativeEntityActivation");add_child(pool)
	if not pool.configure(store,capacity):pool.free();pool=null;return false
	renderer=ClassDB.instantiate("NativeEntityRenderer");add_child(renderer)
	var mesh:=CapsuleMesh.new();mesh.radius=0.35;mesh.height=1.8
	var material:=StandardMaterial3D.new();material.albedo_color=Color("edb35a");mesh.material=material
	if not renderer.configure(store,mesh,256):renderer.free();renderer=null;pool.free();pool=null;return false
	return true
func suspend() -> void:
	if pool!=null:pool.select(Vector3(NAN,0,0),0,1)
	if renderer!=null:renderer.refresh(Vector3(NAN,0,0),0,1)
	status={};simulation_status={};_suspended=true;_selection_time=0;_render_time=0
func _restore(data: PackedByteArray) -> bool:
	if not store.validate_snapshot(data):return false
	suspend()
	return store.restore_storage_snapshot(data)
func select_near(focus: Vector3) -> Dictionary:
	if pool==null:return {"ok":false,"reason":"simulation_disabled"}
	status=pool.select(focus,48,4096)
	renderer.refresh(focus,64,4096)
	return status
func spawn(point: Vector3) -> int:
	if store==null:return 0
	var handle: int=store.spawn(point,Vector3.ZERO)
	return store.persistent_id(handle) if handle!=0 else 0

func update_simulation(delta: float,focus: Vector3,available: bool,readiness: Callable) -> void:
	if pool==null:return
	if not available:
		if not _suspended:suspend()
		return
	_selection_time-=delta;_render_time-=delta
	if _suspended or _selection_time<=0:
		status=pool.select(focus,48,4096);_selection_time=0.2;_suspended=false
	simulation_status=pool.settle(delta,readiness)
	if _render_time<=0:
		renderer.refresh(focus,64,4096);_render_time=0.1
