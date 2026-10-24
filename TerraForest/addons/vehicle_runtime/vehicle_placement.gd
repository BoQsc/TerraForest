# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded click-time admission. Native block/physics queries own the geometry.
static func at_ground(world:Node,session:Node,hit:Dictionary,heading:Basis)->Dictionary:
	if hit.is_empty() or hit.normal.dot(Vector3.UP)<.9:return {"ok":false,"reason":"Aim at nearby level ground"}
	var ground:Vector3=hit.position
	var bounds:=AABB(ground-Vector3(3.25,2,3.25),Vector3(6.5,5,6.5))
	if not session.ready_bounds(world,bounds):return {"ok":false,"reason":"Vehicle area is still loading"}
	var extent:Vector3=(heading*Vector3(1.1,0,2.2)).abs().max((heading*Vector3(-1.1,0,2.2)).abs())
	var footprint:=AABB(ground-Vector3(extent.x,0,extent.z),Vector3(extent.x*2,1.8,extent.z*2))
	var highest:float=ground.y
	if "blocks" in world.structures:
		var fit:Dictionary=world.structures.blocks.placement_support(footprint,ground,false,false,[world.player.get_rid()])
		if not fit.ok or fit.hits<9:return {"ok":false,"reason":"Vehicle needs supported, reasonably level ground across its whole footprint"}
		highest=fit.maximum
	else:
		# Standalone addon hosts can omit NativeBlockWorld; retain the same nine
		# native physics samples and finite height/spread bounds for those hosts.
		var lowest:=INF
		for x:float in [.08,.5,.92]:
			for z:float in [.08,.5,.92]:
				var start:=Vector3(footprint.position.x+footprint.size.x*x,ground.y+1.5,footprint.position.z+footprint.size.z*z)
				var support:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,start-Vector3.UP*3,3,[world.player.get_rid()]))
				if support.is_empty() or support.normal.y<.35:return {"ok":false,"reason":"Vehicle footprint has missing support"}
				highest=maxf(highest,support.position.y);lowest=minf(lowest,support.position.y)
		if highest-lowest>.6 or highest-ground.y>.8:return {"ok":false,"reason":"Vehicle ground is too uneven"}
	var at:=Vector3(ground.x,highest+.85,ground.z)
	if AABB(at-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5)).has_point(world.player.global_position):return {"ok":false,"reason":"Place vehicle farther from the player"}
	var box:=BoxShape3D.new();box.size=Vector3(2.2,1.8,4.4)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.transform=Transform3D(heading,at+Vector3.UP*.3);query.collision_mask=15
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {"ok":false,"reason":"Vehicle space is obstructed"}
	return {"ok":true,"pose":Transform3D(heading,at),"reason":""}

static func find(world:Node,session:Node,nearby:bool)->Dictionary:
	var heading:=Basis(Vector3.UP,world.player.global_rotation.y+PI)
	var space:PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	if not nearby:
		var start:Vector3=world.camera.global_position
		return at_ground(world,session,space.intersect_ray(PhysicsRayQueryParameters3D.create(start,start-world.camera.global_basis.z*12,3,[world.player.get_rid()])),heading)
	# The menu action deliberately needs no precision camera aim. Try nine
	# visible positions ahead, within the already streamed neighbourhood.
	var forward:Vector3=heading.z;var side:Vector3=heading.x
	var reason:="No supporting ground nearby"
	for distance:float in [5.0,7.0,9.0]:
		for offset:float in [0.0,3.0,-3.0]:
			var point:Vector3=world.player.global_position+forward*distance+side*offset
			var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*4,point-Vector3.UP*6,3,[world.player.get_rid()]))
			if hit.is_empty():continue
			var eye:Vector3=world.camera.global_position;var goal:Vector3=hit.position+Vector3.UP
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,goal,7,[world.player.get_rid()])).is_empty():reason="Nearby vehicle space is hidden behind an obstacle";continue
			var candidate:=at_ground(world,session,hit,heading)
			if candidate.ok:return candidate
			reason=candidate.reason
	return {"ok":false,"reason":"No clear nearby vehicle space · "+reason}
