# SPDX-License-Identifier: 0BSD
extends RefCounted
## Only residency glue. Native graph, collision and schedulers own all hot work.
var game:Node
var last_points:=PackedVector3Array()
var next_refresh:=0
var rejected_points:=0
var service_points:=PackedVector3Array()
var local_points:=PackedVector3Array()
var last_service:=false
func set_service(points:PackedVector3Array)->void:
	if points.size()>3:return
	for point in points:
		if not point.is_finite() or point.length()>8192:return
	service_points=points
	next_refresh=0
	_publish(local_points)
func update(points:PackedVector3Array)->void:
	if not is_instance_valid(game):return
	var now:=Time.get_ticks_msec()
	if now<next_refresh and (not points.is_empty() or local_points.is_empty()):return
	next_refresh=now+250
	local_points=points
	_publish(points)
func _publish(points:PackedVector3Array)->void:
	if not is_instance_valid(game):return
	var doors:Dictionary=game.doors.breakable_navigation(64)
	if not game.zombies.navigator.set_interactions_scoped(doors.bodies,doors.bounds):
		game.zombies.navigator.set_interactions(doors.bodies)
	var admitted:=PackedVector3Array()
	for point in service_points:admitted.append(point.snapped(Vector3(4,1,4)))
	for point in points:
		# Current encounter domain fits inside existing 384 m saved-model/block
		# paging coverage. Do not move player focus or request arbitrary world data.
		if admitted.size()>=8:break
		if not point.is_finite() or point.distance_to(game.player.global_position)>96:
			rejected_points+=1;continue
		admitted.append(point.snapped(Vector3(4,1,4)))
	var service:=not service_points.is_empty()
	if admitted==last_points and service==last_service:return
	last_points=admitted;last_service=service
	game.terrain.set_navigation_interest(admitted,service)
	game.structures.blocks.set_navigation_interest(admitted)
	for collection:Node3D in game.structures._models.values():collection.set_navigation_interest(admitted)
	if game.vegetation.trunk_collision!=null:game.vegetation.trunk_collision.set_navigation_interest(admitted)
	if game.ground_enabled and game.ground_cover.rock_collision!=null:game.ground_cover.rock_collision.set_navigation_interest(admitted)
