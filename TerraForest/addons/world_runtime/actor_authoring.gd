# SPDX-License-Identifier: 0BSD
extends RefCounted
# Explicit editor actions only. Runtime selection and simulation remain native.
var selected_identity:=0
var selected_epoch:=-1
func unavailable(world: Node) -> String:
	if world.actors.pool==null:return "Actor simulation is disabled; launch with --actors."
	if world.construction_inventory.gameplay:return "Actor placement is available in the free editor only."
	if world.loading_active or world.shutdown_requested or world.terrain.pending_edit or not world.terrain.world_ready or world.world_vehicle.driving or world.player_hud.inventory_open or not world.app_focused or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return "Actor editing unavailable right now."
	return ""

func apply(world: Node,remove: bool) -> String:
	var blocked:=unavailable(world)
	if not blocked.is_empty():return blocked
	var origin: Vector3=world.camera.global_position
	var ray:=PhysicsRayQueryParameters3D.create(origin,origin-world.camera.global_basis.z*12,0xFFFFFFFF,[world.player.get_rid()])
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return "Aim at a nearby actor." if remove else "Aim at clear, supported ground within 12 m."
	if remove:
		if hit.collider.get_parent()!=world.actors.pool:return "Aim directly at an active actor to remove it."
		var query: Dictionary=world.actors.store.query_sphere_nearest(hit.collider.global_position,0.01,1,64)
		if not query.ok or not query.complete or query.ids.size()!=1:return "Actor selection is ambiguous; try again."
		var identity: int=world.actors.store.persistent_id(query.ids[0])
		if not world.actors.store.despawn(query.ids[0]):return "Actor changed; try again."
		world.actors.orders.clear_target(identity)
		world.actors.select_near(world.terrain.focus)
		return "Actor removed · F5 saves world."
	if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:return "Place actors on static ground or floors, not moving bodies."
	if hit.normal.dot(Vector3.UP)<0.8:return "Choose more level ground for the actor."
	var point: Vector3=hit.position+Vector3.UP*0.93
	var bounds:=AABB(point-Vector3(0.4,1.2,0.4),Vector3(0.8,2.2,0.8))
	if not world._actor_collision_ready(bounds):return "Actor area is still loading."
	if world.lakes.depth_at(point-Vector3.UP*0.8)>0:return "Place the actor on dry ground."
	var neighbours: Dictionary=world.actors.store.query_sphere(point,1.0,1,64)
	if not neighbours.ok or not neighbours.complete or not neighbours.ids.is_empty():return "Another actor occupies this position."
	var shape:=CapsuleShape3D.new();shape.radius=0.35;shape.height=1.8
	var overlap:=PhysicsShapeQueryParameters3D.new();overlap.shape=shape;overlap.transform=Transform3D(Basis(),point);overlap.collision_mask=0xFFFFFFFF
	if not world.get_world_3d().direct_space_state.intersect_shape(overlap,1).is_empty():return "Actor space is occupied; choose clear ground."
	if world.actors.spawn(point)==0:return "Actor storage capacity reached."
	world.actors.select_near(world.terrain.focus)
	return "Actor placed · F5 saves world."

func command(world: Node,stop: bool) -> String:
	var blocked:=unavailable(world)
	if not blocked.is_empty():return blocked
	if selected_epoch!=world.terrain.epoch or world.actors.store.resolve_identity(selected_identity)==0:selected_identity=0
	if stop:
		if selected_identity==0:return "Select an actor with K first."
		world.actors.orders.clear_target(selected_identity)
		return "Actor stopped · F5 saves world."
	var origin: Vector3=world.camera.global_position
	var ray:=PhysicsRayQueryParameters3D.create(origin,origin-world.camera.global_basis.z*12,0xFFFFFFFF,[world.player.get_rid()])
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return "Aim at an actor or a nearby destination."
	if hit.collider.get_parent()==world.actors.pool:
		var query: Dictionary=world.actors.store.query_sphere_nearest(hit.collider.global_position,0.01,1,64)
		if not query.ok or not query.complete or query.ids.size()!=1:return "Actor selection is ambiguous."
		selected_identity=world.actors.store.persistent_id(query.ids[0]);selected_epoch=world.terrain.epoch
		return "Actor selected · aim at ground and press K to move; Shift+K stops."
	if selected_identity==0:return "Aim at an actor and press K first."
	if hit.collider is CharacterBody3D or hit.collider is RigidBody3D or hit.normal.dot(Vector3.UP)<0.8:return "Choose a level static destination."
	var point: Vector3=hit.position+Vector3.UP*0.93
	if not world._actor_collision_ready(AABB(point-Vector3(0.4,1.2,0.4),Vector3(0.8,2.2,0.8))):return "Destination area is still loading."
	if world.lakes.depth_at(point-Vector3.UP*0.8)>0:return "Choose a dry destination."
	var shape:=CapsuleShape3D.new();shape.radius=0.35;shape.height=1.8
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis(),point);query.collision_mask=0xFFFFFFFF
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return "Destination space is occupied."
	if not world.actors.orders.set_target(selected_identity,point):return "Actor changed; select it again."
	return "Actor moving directly toward destination; obstacles can stop it · F5 saves."
