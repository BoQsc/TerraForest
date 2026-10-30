# SPDX-License-Identifier: 0BSD
extends RefCounted
## Only residency glue. Native graph, collision and schedulers own all hot work.
var game:Node
var last_points:=PackedVector3Array()
var next_refresh:=0
var rejected_points:=0
var last_doors:Array[RID]=[]
func update(points:PackedVector3Array)->void:
	if not is_instance_valid(game):return
	var now:=Time.get_ticks_msec()
	if now<next_refresh and not points.is_empty():return
	next_refresh=now+250
	var doors:Array[RID]=game.doors.breakable_bodies(64)
	if doors!=last_doors:
		last_doors=doors;game.zombies.navigator.set_interactions(doors)
	var admitted:=PackedVector3Array()
	for point in points:
		# Current encounter domain fits inside existing 384 m saved-model/block
		# paging coverage. Do not move player focus or request arbitrary world data.
		if admitted.size()>=8:break
		if not point.is_finite() or point.distance_to(game.player.global_position)>96:
			rejected_points+=1;continue
		admitted.append(point.snapped(Vector3(4,1,4)))
	if admitted==last_points:return
	last_points=admitted
	game.terrain.set_navigation_interest(admitted)
	game.structures.blocks.set_navigation_interest(admitted)
	for collection:Node3D in game.structures._models.values():collection.set_navigation_interest(admitted)
	if game.vegetation.trunk_collision!=null:game.vegetation.trunk_collision.set_navigation_interest(admitted)
