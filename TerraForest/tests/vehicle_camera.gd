# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var follow: RefCounted=ClassDB.instantiate("NativeVehicleCamera")
	var body:=RigidBody3D.new();body.freeze=true;root.add_child(body);body.position=Vector3(0,1,0)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,4,-7.2)
	check(follow.update(body,camera,1.0/60) and camera.position.is_equal_approx(Vector3(0,4,-7.2)),"clear camera retains intended distance")
	var wall:=StaticBody3D.new();wall.collision_layer=2
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(20,10,.2);collider.shape=shape
	wall.add_child(collider);root.add_child(wall);wall.position=Vector3(0,2,-3)
	await physics_frame;await physics_frame
	check(follow.update(body,camera,1.0/60) and camera.position.z> -2.7 and camera.position.z< -2,"camera volume stops before building wall")
	for tick in 60: follow.update(body,camera,1.0/60)
	check(camera.position.z> -2.7,"smoothing cannot push camera through wall")
	wall.free();await physics_frame;await physics_frame
	for tick in 120: follow.update(body,camera,1.0/60)
	check(camera.position.z< -7.19,"camera extends after obstruction disappears")
	var before: Vector3=camera.position
	check(not follow.update(body,camera,NAN) and camera.position==before,"invalid time step cannot corrupt camera")
	var self_shape:=CollisionShape3D.new();var self_box:=BoxShape3D.new();self_box.size=Vector3(2,2,4);self_shape.shape=self_box;body.add_child(self_shape)
	await physics_frame;await physics_frame
	check(follow.update(body,camera,1.0/60) and camera.position.z< -7.19,"vehicle body excluded from camera sweep")
	body.free();camera.free();quit(0 if failures==0 else 1)
