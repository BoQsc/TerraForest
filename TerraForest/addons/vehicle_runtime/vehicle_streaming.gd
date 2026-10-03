# SPDX-License-Identifier: 0BSD
# Orchestration only: terrain and structure bounds queries run in native code.
extends RefCounted
var terrain: Node
var structures: Node
var structures_required:=false
var waiting:=false
var _linear:=Vector3.ZERO
var _angular:=Vector3.ZERO
func update(car: RigidBody3D,policy: RefCounted,delta: float) -> bool:
	if not is_instance_valid(terrain):
		# Loss of the bound world must not silently disable the readiness guard.
		_hold(car)
		return false
	var velocity: Vector3=_linear if waiting else car.linear_velocity
	terrain.focus=car.global_position
	terrain.require_collision=true
	terrain.travel_velocity=velocity
	var bounds: AABB=policy.travel_bounds(car.global_position,velocity,delta)
	var ready: bool=terrain.is_collision_region_ready(bounds)
	if structures_required:
		ready=ready and is_instance_valid(structures) and structures.is_collision_region_ready(bounds)
	if not ready:
		_hold(car)
		return false
	if waiting:
		car.freeze=false
		car.linear_velocity=_linear;car.angular_velocity=_angular
		waiting=false
	return true
func _hold(car: RigidBody3D) -> void:
	if waiting or car.freeze: return
	_linear=car.linear_velocity;_angular=car.angular_velocity
	car.freeze=true
	waiting=true
