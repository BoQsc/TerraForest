# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded scene lifecycle only; spatial selection and driving remain native.
const CAPACITY:=4
var owner: Node
var residents: Dictionary={}
var bodies: Array[RigidBody3D]=[]
var timer:=0.0
var status: Dictionary={}
var parked_view: Node3D
var parked_views: Dictionary = {}
var parked_status: Dictionary={}
func _init(session: Node) -> void:owner=session
func sync_records() -> bool:
	for id: int in residents:
		var body: RigidBody3D=residents[id]
		if not is_instance_valid(body) or not owner.sync_body(id,body):return false
	return true
func retire(id: int) -> void:
	var body: RigidBody3D=residents[id]
	owner.adapter(body).controls(body,false);body.freeze=true;body.set_physics_process(false)
	body.collision_layer=0;body.collision_mask=0;body.hide();residents.erase(id)
	if owner.car==body:owner.car=null;owner.car_identity=0
func reset() -> void:
	for view: Node3D in parked_views.values(): view.refresh(Vector3(NAN,0,0),0,PackedInt64Array(),1)
	for id: int in residents.keys():retire(id)
	timer=0
func admit(world: Node,id: int,requested:bool=false) -> bool:
	if residents.has(id):return true
	var record: Dictionary=owner.fleet.get_record(id)
	if not record.present or not owner.packs.vehicles.has(record.kind):return false
	var pose: Transform3D=record.pose
	if not requested and not owner.ready_bounds(world,AABB(pose.origin-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5))):return false
	var body: RigidBody3D
	for candidate in bodies:
		if not residents.values().has(candidate) and owner.kind_of(candidate)==record.kind:body=candidate;break
	if body==null:
		if not owner.scene_ready(record.kind) or not reserve_body_slot():return false
		var previous: RigidBody3D=owner.car;var previous_id: int=owner.car_identity
		owner.car_identity=id
		var installed: bool=owner._install_vehicle(world,pose,record.kind,record.state)
		body=owner.car if installed else null
		owner.car=previous;owner.car_identity=previous_id
		if body==null:return false
		bodies.append(body)
	else:
		if not owner.adapter(body).restore_state(body,record.state):return false
		owner.adapter(body).restore_parked(body,pose)
	body.collision_layer=4;body.collision_mask=15
	body.show();residents[id]=body
	if not parked_views.has(record.kind):prepare_parked_view(world,body)
	return true
func reserve_body_slot() -> bool:
	if bodies.size()<CAPACITY:return true
	for body: RigidBody3D in bodies:
		if not residents.values().has(body):
			bodies.erase(body);body.free();return true
	return false
func parked_identity(collider: Object, rid: RID) -> int:
	for view: Node3D in parked_views.values():
		if collider==view:return view.identity_for_body(rid)
	return 0
func prepare_parked_view(world: Node,body: RigidBody3D) -> void:
	var parts: Array=[]
	var inverse: Transform3D=body.global_transform.affine_inverse()
	for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.is_visible_in_tree():parts.append({"mesh":node.mesh,"transform":inverse*node.global_transform,"material":node.material_override})
	var view: Node3D=ClassDB.instantiate("NativeParkedVehicleRenderer");world.add_child(view)
	var chassis: CollisionShape3D=owner.adapter(body).collision(body)
	var kind: String=owner.kind_of(body)
	if chassis==null or not view.configure(owner.fleet,parts,64,kind) or not view.configure_collision(chassis.shape,body.global_transform.affine_inverse()*chassis.global_transform):parked_status={"ok":false,"reason":"prototype_configuration","parts":parts.size()};view.free();return
	parked_views[kind]=view
	if kind==owner.Packs.DEFAULT:parked_view=view
func prepare_from_saved(world: Node) -> bool:
	var nearby: Dictionary=owner.fleet.query_near(world.terrain.focus,128,256,4096)
	if not nearby.ok or not nearby.complete:return false
	for id: int in nearby.ids:
		var record: Dictionary=owner.fleet.get_record(id)
		if not owner.packs.vehicles.has(record.kind) or parked_views.has(record.kind):continue
		if not owner.scene_ready(record.kind):continue
		for template: RigidBody3D in bodies:
			if owner.kind_of(template)!=record.kind:continue
			var was_visible:=template.visible
			template.show();prepare_parked_view(world,template);template.visible=was_visible
			return parked_views.has(record.kind)
		if not reserve_body_slot():return true
		var previous: RigidBody3D=owner.car;var previous_id: int=owner.car_identity
		owner.car_identity=id
		if owner._install_vehicle(world,record.pose,record.kind,record.state):
			var template: RigidBody3D=owner.car
			template.collision_layer=0;template.collision_mask=0;template.hide();bodies.append(template)
		owner.car=previous;owner.car_identity=previous_id
		return false # Prototype batches are built on a subsequent activation tick.
	return true
func refresh_parked(world: Node) -> void:
	var rendered:=0;var uploaded:=0;var identities:=PackedInt64Array();var okay:=true
	for view: Node3D in parked_views.values():
		var result: Dictionary=view.refresh(world.terrain.focus,128,PackedInt64Array(residents.keys()),4096)
		okay=okay and result.ok;rendered+=result.rendered;uploaded+=result.upload_bytes
		identities.append_array(result.get("ids",PackedInt64Array()))
	parked_status={"ok":okay,"rendered":rendered,"upload_bytes":uploaded,"ids":identities}
func place(world: Node,pose: Transform3D) -> String:
	if residents.size()>=CAPACITY:return "Nearby vehicle capacity reached; move farther before placing another."
	var nearby: Dictionary=owner.fleet.query_near(pose.origin,7,256,4096)
	if not nearby.ok or not nearby.complete or nearby.get("truncated",false):return "Vehicle occupancy query is incomplete."
	for identity: int in nearby.ids:
		var parked: Vector3=owner.fleet.get_record(identity).pose.origin
		if AABB(parked-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5)).has_point(pose.origin):return "Another saved vehicle occupies this area."
	var id: int=owner.fleet.spawn(pose)
	if id==0:return "Vehicle storage rejected placement."
	if not admit(world,id):owner.fleet.remove(id);return "Vehicle activation unavailable."
	owner.last_spawn_identity=id
	return "Vehicle placed · E nearby to enter · F5 saves world"
func place_requested(world:Node,pose:Transform3D,kind: String= "terraforest.ranger.v1")->String:
	if residents.size()>=CAPACITY:
		var retired:=0;var farthest:=-1.0
		for id:int in residents:
			if owner.driving and id==owner.car_identity:continue
			var distance:float=residents[id].global_position.distance_squared_to(world.player.global_position)
			if distance>farthest:retired=id;farthest=distance
		if retired>0:
			if not owner.sync_body(retired,residents[retired]):return "Vehicle state could not be saved"
			owner.coasting.erase(retired);retire(retired)
	var id:int=owner.fleet.spawn_module(pose,kind)
	if id==0:return "Vehicle storage could not create the vehicle"
	if not admit(world,id,true):owner.fleet.remove(id);return "Vehicle model could not be created"
	owner.last_spawn_identity=id;refresh_parked(world)
	return "Vehicle spawned nearby"
func select_for_entry(point: Vector3,expected:int=0) -> void:
	if parked_views.is_empty():
		owner.car=null;owner.car_identity=0;timer=0;return
	var query: Dictionary=owner.fleet.query_near(point,3.5,1,4096)
	if expected>0:
		var record:Dictionary=owner.fleet.get_record(expected)
		query={"ok":record.present,"complete":true,"ids":PackedInt64Array([expected]) if record.present and record.pose.origin.distance_to(point)<=3.5 else PackedInt64Array()}
	if query.ok and query.complete and not query.ids.is_empty() and not residents.has(query.ids[0]):
		if sync_records():
			if residents.size()>=CAPACITY:
				var farthest:=0;var distance:=-1.0
				for id: int in residents:
					if owner.coasting.has(id):continue
					var candidate: float=residents[id].global_position.distance_squared_to(point)
					if candidate>distance:distance=candidate;farthest=id
				if farthest==0:return
				retire(farthest)
			admit(owner._world,query.ids[0]);refresh_parked(owner._world)
	var nearest:=3.5;var chosen:=0
	for id: int in residents:
		if expected>0 and id!=expected:continue
		var distance: float=residents[id].global_position.distance_to(point)
		if distance<nearest or (is_equal_approx(distance,nearest) and (chosen==0 or id<chosen)):nearest=distance;chosen=id
	owner.car=residents.get(chosen);owner.car_identity=chosen
func overlaps_edit(bounds: AABB) -> bool:
	var radius: float=bounds.size.length()*0.5+5
	if radius>128:return owner.fleet.statistics().records>0
	var result: Dictionary=owner.fleet.query_near(bounds.get_center(),radius,256,4096)
	if not result.ok or not result.complete or result.get("truncated",false):return true
	for id: int in result.ids:
		var p: Vector3=residents[id].global_position if residents.has(id) else owner.fleet.get_record(id).pose.origin
		if AABB(p-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5)).intersects(bounds):return true
	return false
func update(world: Node,delta: float) -> void:
	if "loading_active" in world and (world.loading_active or world.shutdown_requested):return
	timer-=delta
	if timer>0:return
	timer=0.2
	if not sync_records():status={"ok":false,"reason":"invalid_live_pose"};return
	if not prepare_from_saved(world):return
	status=owner.fleet.query_near(world.terrain.focus,64,256,4096)
	if not status.ok or not status.complete:return
	var wanted:=PackedInt64Array()
	for identity: int in status.ids:
		if owner.packs.vehicles.has(owner.fleet.get_record(identity).kind):wanted.append(identity)
		if wanted.size()>=CAPACITY:break
	var pinned:Array=owner.coasting.keys()
	if owner.driving:pinned.append(owner.car_identity)
	for id:int in pinned:
		if wanted.has(id):continue
		if wanted.size()>=CAPACITY:
			for index in range(wanted.size()-1,-1,-1):
				if not pinned.has(wanted[index]):wanted.remove_at(index);break
		if wanted.size()<CAPACITY:wanted.append(id)
	for id: int in residents.keys():
		if not wanted.has(id):retire(id)
	# At most one expensive model instantiation/admission per selection tick.
	for id: int in wanted:
		if not residents.has(id):admit(world,id);break
	refresh_parked(world)
