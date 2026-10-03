# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var native: RefCounted=ClassDB.instantiate("NativeVehicleSuspension")
	var floor:=StaticBody3D.new();var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new()
	shape.size=Vector3(20,0.2,20);collider.shape=shape;floor.add_child(collider);root.add_child(floor);floor.position.y=-0.1
	var body:=RigidBody3D.new();body.freeze=true;root.add_child(body);body.position.y=0.7
	var rays: Array[RayCast3D]=[]
	for i in 4:
		var ray:=RayCast3D.new();ray.enabled=false;ray.target_position=Vector3(0,-0.906,0)
		body.add_child(ray);ray.position=Vector3((i%2)*2-1,0,(i/2)*2-1);rays.append(ray)
	await physics_frame;await physics_frame
	var values: PackedFloat32Array=native.sample_and_apply(body,rays)
	var supported:=values.size()==40
	for i in 4: supported=supported and values[i*10]==1 and values[i*10+1]==1 and absf(values[i*10+3]-2970)<2
	check(supported,"disabled automatic rays still produce native load and original spring force")
	body.linear_velocity=Vector3(0,-100,0)
	values=native.sample_and_apply(body,rays)
	check(values[3]==12000,"compression force is capped")
	body.linear_velocity=Vector3(0,100,0)
	values=native.sample_and_apply(body,rays)
	check(values[3]==0,"rebound force never pulls body into ground")
	body.linear_velocity=Vector3.ZERO;body.position.y=3
	values=native.sample_and_apply(body,rays)
	check(values[0]==0 and values[1]==0 and values[3]==0,"airborne wheel has no support force")
	check(native.sample_and_apply(body,[]).is_empty(),"incomplete wheel set rejected")
	body.free();floor.free();quit(1 if failures else 0)
