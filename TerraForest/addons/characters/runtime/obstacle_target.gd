# SPDX-License-Identifier: 0BSD
extends Node3D
## A host-authorized breakable surface; never a proximity-based damage source.
var surface: Node3D
var body_rid: RID
var identity := 0
var contact_point := Vector3.ZERO
var approach_point := Vector3.ZERO
var shape_pose := Transform3D.IDENTITY
var half_extents := Vector3(0.5,1.1,0.07)
var damage_callback: Callable
var validity: Callable

func available() -> bool:
	return is_instance_valid(surface) and validity.is_valid() and bool(validity.call())

func get_zombie_attack_target_point(_action: String) -> Vector3:
	return contact_point

func get_zombie_attack_radius() -> float:
	return 0.12

func get_zombie_attack_contact_shapes(_action: String) -> Array:
	return [{"type":"box","transform":shape_pose,"half_extents":half_extents}]

func accepts_zombie_attack_surface(hit: Dictionary) -> bool:
	return available() and hit.get("collider")==surface and hit.get("rid")==body_rid

func receive_zombie_attack(damage: float) -> void:
	if available() and damage_callback.is_valid():damage_callback.call(damage)
