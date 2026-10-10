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
var parked_status: Dictionary={}
func _init(session: Node) -> void:owner=session
func sync_records() -> bool:
	for id: int in residents:
		var body: RigidBody3D=residents[id]
		if not is_instance_valid(body) or not owner.fleet.set_pose(id,body.global_transform):return false
	return true
func retire(id: int) -> void:
	var body: RigidBody3D=residents[id]
	body.set_controls_enabled(false);body.freeze=true;body.set_physics_process(false)
	body.collision_layer=0;body.collision_mask=0;body.hide();residents.erase(id)
	if owner.car==body:owner.car=null;owner.car_identity=0
func reset() -> void:
	if is_instance_valid(parked_view):parked_view.refresh(Vector3(NAN,0,0),0,PackedInt64Array(),1)
	for id: int in residents.keys():retire(id)
	timer=0
func admit(world: Node,id: int) -> bool:
	if residents.has(id):return true
	var record: Dictionary=owner.fleet.get_record(id)
	if not record.present:return false
	var pose: Transform3D=record.pose
	if not owner.ready_bounds(world,AABB(pose.origin-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5))):return false
	var body: RigidBody3D
	for candidate in bodies:
		if not residents.values().has(candidate):body=candidate;break
	if body==null:
		if bodies.size()>=CAPACITY or not owner.scene_ready():return false
		var previous: RigidBody3D=owner.car;var previous_id: int=owner.car_identity
		owner.car_identity=id
		var installed: bool=owner._install_vehicle(world,pose)
		body=owner.car if installed else null
		owner.car=previous;owner.car_identity=previous_id
		if body==null:return false
		bodies.append(body)
	else:body.restore_parked(pose)
	body.collision_layer=4;body.collision_mask=7
	for wheel in body.wheel_rays:
		wheel.collision_mask=7;wheel.add_exception(body)
	body.show();residents[id]=body
	if parked_view==null:prepare_parked_view(world,body)
	return true
func prepare_parked_view(world: Node,body: RigidBody3D) -> void:
	var parts: Array=[]
	var inverse: Transform3D=body.global_transform.affine_inverse()
	for node: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.is_visible_in_tree():parts.append({"mesh":node.mesh,"transform":inverse*node.global_transform,"material":node.material_override})
	var view: Node3D=ClassDB.instantiate("NativeParkedVehicleRenderer");world.add_child(view)
	var chassis: CollisionShape3D=body.get_node("ChassisCollision")
	if not view.configure(owner.fleet,parts,64) or not view.configure_collision(chassis.shape,chassis.transform):parked_status={"ok":false,"reason":"prototype_configuration","parts":parts.size()};view.free();return
	parked_view=view
func prepare_from_saved(world: Node) -> void:
	if parked_view!=null or not bodies.is_empty() or not owner.scene_ready():return
	var nearby: Dictionary=owner.fleet.query_near(world.terrain.focus,128,1,4096)
	if not nearby.ok or not nearby.complete or nearby.ids.is_empty():return
	var id: int=nearby.ids[0]
	var previous: RigidBody3D=owner.car;var previous_id: int=owner.car_identity
	owner.car_identity=id
	if owner._install_vehicle(world,owner.fleet.get_record(id).pose):
		var template: RigidBody3D=owner.car
		prepare_parked_view(world,template)
		template.collision_layer=0;template.collision_mask=0;template.hide();bodies.append(template)
	owner.car=previous;owner.car_identity=previous_id
func refresh_parked(world: Node) -> void:
	if parked_view!=null:parked_status=parked_view.refresh(world.terrain.focus,128,PackedInt64Array(residents.keys()),4096)
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
	return "Vehicle placed · E nearby to enter · F5 saves world"
func select_for_entry(point: Vector3) -> void:
	var query: Dictionary=owner.fleet.query_near(point,3.5,1,4096)
	if query.ok and query.complete and not query.ids.is_empty() and not residents.has(query.ids[0]):
		if sync_records():
			if residents.size()>=CAPACITY:
				var farthest:=0;var distance:=-1.0
				for id: int in residents:
					var candidate: float=residents[id].global_position.distance_squared_to(point)
					if candidate>distance:distance=candidate;farthest=id
				retire(farthest)
			admit(owner._world,query.ids[0]);refresh_parked(owner._world)
	var nearest:=3.5;var chosen:=0
	for id: int in residents:
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
	prepare_from_saved(world)
	status=owner.fleet.query_near(world.terrain.focus,64,CAPACITY,4096)
	if not status.ok or not status.complete:return
	var wanted: PackedInt64Array=status.ids
	if owner.driving and not wanted.has(owner.car_identity):
		if wanted.size()>=CAPACITY:wanted.resize(CAPACITY-1)
		wanted.append(owner.car_identity)
	for id: int in residents.keys():
		if not wanted.has(id):retire(id)
	# At most one expensive model instantiation/admission per selection tick.
	for id: int in wanted:
		if not residents.has(id):admit(world,id);break
	refresh_parked(world)
