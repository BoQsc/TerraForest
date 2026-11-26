# SPDX-License-Identifier: 0BSD
extends RefCounted
## Shared placement calculation for authored, upright wall-mounted objects.
static func target(entry: Dictionary, hit: Dictionary, snap_step: float=0.1, turns: int=0) -> Dictionary:
	var normal: Vector3 = hit.get("normal",Vector3.UP)
	if absf(normal.y)>0.15: return {"placement_ok":false,"reason":"Aim at a vertical wall"}
	normal=Vector3(normal.x,0,normal.z).normalized()
	var basis := Basis.looking_at(normal,Vector3.UP)*Basis(Vector3.FORWARD,turns*PI*0.5)*Basis.from_scale(entry.scale)
	var point: Vector3=hit.position
	if snap_step>0:
		var tangent := Vector3.UP.cross(normal)
		point+=tangent*(snappedf(point.dot(tangent),snap_step)-point.dot(tangent))
		point.y=snappedf(point.y,snap_step)
	var local: AABB=entry.mesh.get_aabb()
	var anchor := point-basis*Vector3(local.get_center().x,local.get_center().y,local.end.z)+normal*0.015
	var pose := Transform3D(basis,anchor)
	return {"placement_ok":true,"reason":"","transform":pose,"bounds":pose*local,"normal":normal}

static func supported(blocks: Node3D, entry: Dictionary, pose: Transform3D, exclude: Array) -> bool:
	var points: PackedVector3Array=entry.mesh.get_meta("wall_support_points",PackedVector3Array())
	if points.is_empty(): return false
	var normal := -pose.basis.z.normalized()
	for point: Vector3 in points:
		var expected := pose*point
		var hit: Dictionary=blocks.raycast_scene(expected+normal*0.08,expected-normal*0.16,3,exclude)
		if hit.is_empty() or hit.normal.dot(normal)<0.85 or expected.distance_to(hit.position)>0.1: return false
	return true
