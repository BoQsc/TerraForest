# SPDX-License-Identifier: 0BSD
extends Node
## Bounded scene residency/UI glue; contents, identities and save bytes are native.
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var game:Node
var store:RefCounted
var active:Dictionary={}
var pending:Dictionary={}
const PREPARE_BUDGET_US:=1500
var ui=preload("res://addons/player_runtime/storage.gd").new()
var clock:=0.0
var update_profile:Dictionary={}
func prepare(owner_game:Node,persistence:RefCounted)->bool:
	game=owner_game;store=ClassDB.instantiate("NativeCorpseStore")
	if not store.configure(game.player_hud.inventory,4096,8):return false
	ui.prepare_external(game,store,aimed_id)
	return persistence.register_component("zombie_corpses_v1",capture,restore,store,store.capture_corpse_snapshot())
func _ready()->void:add_child(ui)
func retire_location(identities:PackedInt64Array)->void:
	ui.close()
	if not pending.is_empty() and identities.has(int(pending.zombie.get_meta("world_zombie_id",0))):_discard_pending()
	for identity:int in active.keys():
		var zombie:Node3D=active[identity]
		if is_instance_valid(zombie) and identities.has(int(zombie.get_meta("world_zombie_id",0))):
			sync(identity,zombie);active.erase(identity);zombie.queue_free()

func clear_live()->void:
	ui.close()
	_discard_pending()
	for zombie:Node in active.values():
		if is_instance_valid(zombie):zombie.queue_free()
	active.clear()
func _discard_pending()->void:
	if not pending.is_empty() and is_instance_valid(pending.zombie):pending.zombie.queue_free()
	pending.clear()
func _advance_pending(focus:Vector3)->void:
	var zombie:Node3D=pending.zombie
	var point:Vector3=pending.point
	if not is_instance_valid(zombie) or active.size()>=12 or point.distance_to(focus)>96.0 or not game._actor_collision_ready(AABB(point-Vector3(2,1,2),Vector3(4,3,4))):
		_discard_pending();return
	if zombie.prepare_corpse_step(PREPARE_BUDGET_US):
		active[int(zombie.get_meta("corpse_identity"))]=zombie
		zombie.set_simulation_available(true);zombie.show();pending.clear()
func retain(zombie:Node3D)->bool:
	var id:int=zombie.get_meta("corpse_identity",0)
	if id==0:
		var resident:int=zombie.get_meta("world_zombie_id",0)
		var anchor:int=game.zombies.population.store.resident(resident).get("anchor",0) if resident>0 else 0
		id=store.create_corpse(zombie.global_position,zombie.global_rotation.y,game.ecosystem.seed,resident,anchor)
		if id==0:push_error("Corpse storage rejected; corpse retained without loot");return false
		zombie.set_meta("corpse_identity",id);game.terrain.changed_since_save=true
		zombie.set_meta("corpse_save_after",6.0)
	active[id]=zombie;return true
func sync(id:int,zombie:Node3D)->void:
	var poses:=PackedFloat32Array();var missing:=0;var index:=0
	for part:String in zombie.PARTS:
		var removed:bool=zombie.missing.get(part,false)
		if removed:missing|=1<<index
		var pose:Transform3D=zombie.physical_bones.Hips.global_transform if removed else zombie.physical_bones[zombie.PARTS[part].bone].global_transform
		for row in 3:poses.append_array(PackedFloat32Array([pose.basis.x[row],pose.basis.y[row],pose.basis.z[row],pose.origin[row]]))
		index+=1
	var hips:Transform3D=zombie.physical_bones["Hips"].global_transform
	for row in 3:poses.append_array(PackedFloat32Array([hips.basis.x[row],hips.basis.y[row],hips.basis.z[row],hips.origin[row]]))
	if not store.update_corpse(id,zombie.global_position,zombie.global_rotation.y,missing,poses):push_error("Corpse pose capture failed")
func capture()->PackedByteArray:
	for id:int in active:
		if is_instance_valid(active[id]):sync(id,active[id])
	return store.capture_corpse_snapshot()
func restore(bytes:PackedByteArray)->bool:
	if not store.validate_corpse_snapshot(bytes):return false
	clear_live();clock=0.0;return store.restore_corpse_snapshot(bytes)
func aimed_id(_shared_hit:Variant=null)->int:
	var origin:Vector3=game.camera.global_position
	var hit:Dictionary=game.zombies.pick(origin,origin-game.camera.global_basis.z*3.0,[game.player.get_rid()])
	return int(hit.zombie.get_meta("corpse_identity",0)) if not hit.is_empty() and not hit.zombie.alive else 0
func set_frozen(zombie:Node3D,frozen:bool)->void:
	zombie.set_simulation_available(not frozen)
func update(delta:float,focus:Vector3,available:bool)->void:
	var profiling:bool=game.zombies.profiling_enabled
	var begin:=Time.get_ticks_usec() if profiling else 0
	var readiness_us:=0
	var freeze_us:=0
	var sync_us:=0
	for id:int in active.keys():
		var zombie:Node3D=active[id]
		if not is_instance_valid(zombie):active.erase(id);continue
		var point:Vector3=zombie.physical_bones[zombie.PARTS.torso.bone].global_position
		if available and zombie.has_meta("corpse_save_after"):
			var remaining:float=float(zombie.get_meta("corpse_save_after"))-delta
			if remaining<=0:zombie.remove_meta("corpse_save_after");sync(id,zombie);game.terrain.changed_since_save=true
			else:zombie.set_meta("corpse_save_after",remaining)
		var phase_start:=Time.get_ticks_usec() if profiling else 0
		var ready:bool=game._actor_collision_ready(AABB(point-Vector3(2,1,2),Vector3(4,3,4)))
		if profiling:readiness_us+=Time.get_ticks_usec()-phase_start;phase_start=Time.get_ticks_usec()
		set_frozen(zombie,not available or not ready)
		if profiling:freeze_us+=Time.get_ticks_usec()-phase_start;phase_start=Time.get_ticks_usec()
		if available and point.distance_to(focus)>96.0 and not (ui.opened and ui.identity==id):
			sync(id,zombie);game.terrain.changed_since_save=true;active.erase(id);zombie.queue_free()
			if not store.has_contents(id):store.erase_corpse(id);game.terrain.changed_since_save=true
		if profiling:sync_us+=Time.get_ticks_usec()-phase_start
	while active.size()>12:
		var retiring:=0;var farthest:=-1.0
		for id:int in active:
			if ui.opened and ui.identity==id:continue
			var distance:float=active[id].global_position.distance_squared_to(focus)
			if not store.has_contents(id):distance+=1000000.0
			if distance>farthest:retiring=id;farthest=distance
		if retiring==0:break
		sync(retiring,active[retiring]);game.terrain.changed_since_save=true;active[retiring].queue_free();active.erase(retiring)
		if not store.has_contents(retiring):store.erase_corpse(retiring);game.terrain.changed_since_save=true
	if profiling:update_profile={"active":active.size(),"readiness_us":readiness_us,"freeze_us":freeze_us,"retire_us":sync_us,"update_us":Time.get_ticks_usec()-begin,"restore_us":0}
	if not available:return
	clock-=delta
	if not pending.is_empty():
		var prepare_start:=Time.get_ticks_usec() if profiling else 0
		_advance_pending(focus)
		if profiling:update_profile.restore_us=Time.get_ticks_usec()-prepare_start;update_profile.update_us=Time.get_ticks_usec()-begin
		return
	if clock>0 or active.size()>=12:return
	clock=0.5
	var restore_start:=Time.get_ticks_usec() if profiling else 0
	for id:int in store.nearby_corpses(focus,80.0,PackedInt64Array(active.keys())):
		var record:Dictionary=store.corpse(id);var point:Vector3=record.position
		if record.pose.size()==180:point=Vector3(record.pose[3],record.pose[7],record.pose[11])
		if point.distance_to(focus)>80.0 or not game._actor_collision_ready(AABB(point-Vector3(2,1,2),Vector3(4,3,4))):continue
		var zombie=Zombie.new();zombie.capture_collision_clouds=game.zombies.capture_collision_clouds;zombie.geometry_template=game.zombies.geometry_template;zombie.position=record.position;zombie.rotation.y=record.yaw;zombie.hide();game.zombies.add_child(zombie)
		if not zombie.initialized:zombie.queue_free();break
		game.zombies.geometry_template=zombie.anatomy
		zombie.set_meta("corpse_identity",id)
		if int(record.resident)>0:zombie.set_meta("world_zombie_id",int(record.resident))
		if record.pose.size()==180:
			zombie.animation_player.stop(true);zombie.animation_player.active=false
			zombie.skeleton.force_update_all_bone_transforms()
			var original:Array[Transform3D]=[]
			for bone_index in zombie.skeleton.get_bone_count():original.append(zombie.skeleton.get_bone_global_pose(bone_index))
			var restored:Dictionary={}
			var index:=0
			var bones:Array=[]
			for part:String in zombie.PARTS:bones.append(zombie.PARTS[part].bone)
			bones.append("Hips")
			for bone:String in bones:
				if index==14 or (record.missing&(1<<index))==0:
					var offset:=index*12;var values:PackedFloat32Array=record.pose
					var pose:=Transform3D(Basis(Vector3(values[offset],values[offset+4],values[offset+8]),Vector3(values[offset+1],values[offset+5],values[offset+9]),Vector3(values[offset+2],values[offset+6],values[offset+10])),Vector3(values[offset+3],values[offset+7],values[offset+11]))
					var body:PhysicalBone3D=zombie.physical_bones[bone]
					restored[zombie.skeleton.find_bone(bone)]=zombie.skeleton.global_transform.affine_inverse()*pose*body.body_offset.affine_inverse()
				index+=1
			var poses:Array[Transform3D]=original.duplicate()
			for bone_index in poses.size():
				var ancestor:int=bone_index
				while ancestor>=0 and not restored.has(ancestor):ancestor=zombie.skeleton.get_bone_parent(ancestor)
				if ancestor>=0:poses[bone_index]=restored[ancestor]*original[ancestor].affine_inverse()*original[bone_index]
			for bone_index in poses.size():
				var parent:int=zombie.skeleton.get_bone_parent(bone_index)
				zombie.skeleton.set_bone_pose(bone_index,poses[bone_index] if parent<0 else poses[parent].affine_inverse()*poses[bone_index])
			zombie.skeleton.force_update_all_bone_transforms()
		zombie.begin_corpse_restore(record.missing)
		pending={"zombie":zombie,"point":point}
		break
	if profiling:update_profile.restore_us=Time.get_ticks_usec()-restore_start;update_profile.update_us=Time.get_ticks_usec()-begin
