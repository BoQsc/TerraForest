# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
class Coverage extends Node:
	var available:=true
	func _actor_collision_ready(_bounds:AABB)->bool:return available
class AdmissionStore extends RefCounted:
	func initialize(_seed:int,_spawn:Vector3)->bool:return true
class AdmissionGame extends Node:
	var terrain:Dictionary={"backend":{"world_seed":1703},"changed_since_save":false}
	var _initial_generation_spawn:=Vector3.ZERO
class AdmissionHost extends Node3D:
	var enabled:=true
	var population_enabled:=true
	var profiling_enabled:=false
	var residents:Array=[]
	var residency_limit:=6
	var full_ready:=false
	var attempts:=0
	var navigation_interest:Callable
	var readiness:Callable=func(bounds:AABB)->bool:return bounds.size.x<5 or full_ready
	func admission_bounds(point:Vector3,sleeping:bool,authored:bool)->AABB:
		return preload("res://addons/characters/runtime/zombie_world.gd").admission_bounds(point,sleeping,authored)
	func spawn_at(_point:Vector3,_sleeping:bool,_authored:bool,_id:int,_seed:int,_deferred:bool=false)->CharacterBody3D:
		attempts+=1;return null # Fully ready but unsuitable geometry remains a rejection.
var failures:=0
var checks:=0
var stage:Node3D
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func fresh(point:Vector3=Vector3.ZERO,saved_pose:bool=false,missing_mask:int=0)->Node3D:
	var actor:=Zombie.new(saved_pose,missing_mask);actor.position=point;stage.add_child(actor)
	actor.set_behavior(false);actor.animation_player.play(actor._animation_key("Zombie_Attack_Left"))
	actor.animation_player.seek(0.65,true);actor.animation_player.pause()
	return actor
func constraints(actor:Node3D)->Dictionary:
	var result:Dictionary={}
	for bone:String in actor.physical_bones:
		var body:PhysicalBone3D=actor.physical_bones[bone];var values:Dictionary={"type":body.joint_type}
		for property:Dictionary in body.get_property_list():
			if String(property.name).begins_with("joint_constraints/"):values[property.name]=body.get(property.name)
		result[bone]=values
	return result
func admission_coverage()->void:
	var game:=AdmissionGame.new();var host:=AdmissionHost.new()
	var population:=preload("res://addons/characters/runtime/zombie_population.gd").new()
	population.game=game;population.host=host;population.store=AdmissionStore.new()
	population.last_focus=Vector3.ZERO;population.sampled=true;population.began=Time.get_ticks_msec()
	population.queue=[{"id":1,"state":1,"position":Vector3(60,0,0),"anchor":1,"sleep":PackedByteArray()}]
	population.advance(Vector3.ZERO,true)
	check(population.cursor==0 and population.examined==0 and host.attempts==0,"admission waits for the full support footprint instead of skipping a pending resident")
	host.full_ready=true;population.advance(Vector3.ZERO,true)
	check(population.cursor==1 and population.examined==1 and host.attempts==1,"ready but unsuitable geometry still consumes exactly one candidate")
	game.free();host.free()
func clouds(actor:Node3D)->Dictionary:
	var result:Dictionary={}
	for bone:String in actor.physical_bones:
		var points:Array=[]
		for child in actor.physical_bones[bone].get_children():
			if child is CollisionShape3D:points.append(child.shape.points)
		result[bone]=points
	return result
func staged_live_admission()->void:
	var cancelled:=Zombie.new();cancelled.defer_configuration=true;cancelled.hide();cancelled.set_simulation_available(false);stage.add_child(cancelled)
	cancelled.prepare_configuration_step(1)
	var unattached:Node=cancelled.model
	check(unattached!=null and unattached.get_parent()==null,"scene instantiation can yield before tree attachment")
	cancelled.queue_free();await process_frame;await process_frame
	check(not is_instance_valid(unattached),"cancelling before attachment frees the unparented model")
	var floor_body:=StaticBody3D.new();floor_body.position.y=-.5
	var shape:=BoxShape3D.new();shape.size=Vector3(100,1,100)
	var collision:=CollisionShape3D.new();collision.shape=shape;floor_body.add_child(collision);stage.add_child(floor_body)
	var world:=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(world)
	var target:=Node3D.new();stage.add_child(target);target.position=Vector3(40,0,0)
	world.target=target;world.enabled=true;world.readiness=func(_box:AABB)->bool:return true
	await physics_frame
	var actor:CharacterBody3D=world.spawn_at(Vector3.ZERO,false,false,0,1703,true)
	check(actor!=null and world.residents.is_empty() and not actor.initialized and not actor.visible,"live admission begins hidden without entering the resident pool")
	if actor!=null:
		var slices:=0
		while not actor.initialized and not actor.configuration_failed and slices<64:
			actor.prepare_configuration_step(750);slices+=1;await process_frame
		check(actor.initialized and slices>1 and world.residents.is_empty() and not actor.visible and actor.process_mode==Node.PROCESS_MODE_DISABLED,"live configuration spans frames without movement, contacts or early visibility")
		check(world.finish_spawn(actor,0,1703) and world.residents.has(actor),"fully prepared live actor joins ordinary awareness and residency")
		check(not world.finish_spawn(actor,0,1703),"publication cannot register the same actor twice")
	world.clear();world.queue_free();target.queue_free();floor_body.queue_free();await process_frame;await process_frame
func run()->void:
	admission_coverage()
	ProjectSettings.set_setting("physics/3d/default_gravity",0.0)
	stage=Node3D.new();root.add_child(stage)
	var ordinary:=fresh();var original_constraints:=constraints(ordinary)
	ordinary.die();await process_frame;await process_frame
	check(constraints(ordinary)==original_constraints,"death rebinding preserves every authored joint parameter")
	print("IMMEDIATE_RAGDOLL ",JSON.stringify(ordinary.ragdoll_profile))
	var reference:=clouds(ordinary)
	var mask:=0;var index:=0
	for part:String in Zombie.PARTS:
		if part in ["upper_arm_l","forearm_l","hand_l","foot_r"]:mask|=1<<index
		index+=1
	var staged:=fresh(Vector3(10,0,0),true,mask)
	check(staged.physical_bones.size()==11,"saved missing bodies are never constructed")
	var empty_physics:=true
	for body:PhysicalBone3D in staged.physical_bones.values():
		empty_physics=empty_physics and body.joint_type==PhysicalBone3D.JOINT_TYPE_NONE
		for child in body.get_children():
			if child is CollisionShape3D:empty_physics=empty_physics and child.shape==null
	check(empty_physics,"saved-pose admission creates no disposable rest-pose shapes or joints")
	staged.begin_corpse_restore(mask);await process_frame
	check(not staged.visible and not staged.alive and staged.detached_parts.is_empty(),"pending corpse is hidden, dead and creates no disposable debris")
	check(staged.physical_bones.size()==11 and not staged.physical_bones.has("LeftArm"),"known missing anatomy is removed before hull preparation")
	var steps:=0;var partial_safe:=true
	while not staged._ragdoll_started and steps<256:
		for body:PhysicalBone3D in staged.physical_bones.values():partial_safe=partial_safe and body.collision_layer==0
		staged.prepare_corpse_step(1);steps+=1
		if staged._pending_pose_bodies.is_empty():staged.prepare_corpse_step(1500)
		await process_frame
	check(partial_safe and steps>11 and steps<256 and staged._ragdoll_started,"tiny-budget preparation makes progress through worker hulls and individual fingers without publishing partial collision")
	var matched:=true;var actual:=clouds(staged)
	for bone:String in actual:
		if actual[bone].size()!=reference[bone].size():matched=false;continue
		for shape in actual[bone].size():
			if bone=="Head":
				# The engine cleaner returns hull vertices, not the render cloud.
				# Compare independent directional supports; detailed engine contact
				# rays for rest/attack/morph are in zombie_collision_cloud.gd.
				for sample in 128:
					var y:=1.0-2.0*(sample+.5)/128.0;var radius:=sqrt(1-y*y);var angle:=sample*2.399963229728653
					var direction:=Vector3(radius*cos(angle),y,radius*sin(angle))
					var a:=-INF;var b:=-INF
					for point:Vector3 in actual[bone][shape]:a=maxf(a,point.dot(direction))
					for point:Vector3 in reference[bone][shape]:b=maxf(b,point.dot(direction))
					matched=matched and absf(a-b)<.0005
				continue
			if actual[bone][shape].size()!=reference[bone][shape].size():matched=false;continue
			for vertex in actual[bone][shape].size():matched=matched and actual[bone][shape][vertex].distance_to(reference[bone][shape][vertex])<0.0001
	check(matched,"staged collision preserves finger compounds and small clouds exactly; cleaned head support matches within 0.5 mm")
	var same_joints:=true;var restored:=constraints(staged)
	for bone:String in restored:same_joints=same_joints and restored[bone]==original_constraints[bone]
	check(same_joints,"saved anatomy retains the same joints on remaining bodies")
	check(staged.get_meta("corpse_frozen",false),"prepared corpse remains suspended until publication")
	staged.set_simulation_available(true);staged.show()
	var spaces:Dictionary={};var motion:Dictionary={}
	for bone:String in staged.physical_bones:
		var body:PhysicalBone3D=staged.physical_bones[bone]
		body.linear_velocity=Vector3(.2,.3,.4);body.angular_velocity=Vector3(.1,.2,.3)
		spaces[bone]=PhysicsServer3D.body_get_space(body.get_rid())
		motion[bone]=[PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)]
	staged.set_simulation_available(false)
	for repeat in 100:staged.set_simulation_available(false)
	var suspended:=true
	for bone:String in staged.physical_bones:
		var body:PhysicalBone3D=staged.physical_bones[bone]
		suspended=suspended and PhysicsServer3D.body_get_space(body.get_rid())==spaces[bone] and PhysicsServer3D.body_get_mode(body.get_rid())==PhysicsServer3D.BODY_MODE_STATIC
	check(suspended,"idempotent suspension keeps bodies and joints in their physics space")
	staged.sever_limb("hand_r",Vector3.ZERO,false)
	staged.anatomy.wake_ragdolls(AABB(Vector3(-100,-100,-100),Vector3(200,200,200)))
	staged.anatomy.pick(Vector3(10,1.5,2),Vector3(10,1.5,-2))
	staged.anatomy.sample_vertices("head",Transform3D.IDENTITY)
	check(staged.anatomy.ragdoll_stats().bodies==staged.physical_bones.size(),"queries exclude removed nodes before deferred destruction")
	staged.set_simulation_available(true)
	var resumed:=true
	for bone:String in staged.physical_bones:
		var body:PhysicalBone3D=staged.physical_bones[bone]
		resumed=resumed and body.linear_velocity==motion[bone][0] and body.angular_velocity==motion[bone][1] and body.collision_layer==Zombie.RAGDOLL_LAYER
	check(resumed,"resume restores motion even when a suspended limb was removed")
	stage.remove_child(staged)
	check(staged.anatomy.pick(Vector3.ZERO,Vector3.FORWARD).is_empty() and staged.anatomy.sample_vertices("head",Transform3D.IDENTITY).is_empty(),"out-of-tree rigs are unavailable to spatial queries")
	staged.free();ordinary.free();await process_frame
	var living:=fresh()
	living.sever_limb("upper_arm_l",Vector3(1,0,0));living.set_simulation_available(false)
	living.sever_limb("hand_r",Vector3(1,0,0))
	var detached_safe:=true
	for group:RigidBody3D in living.detached_parts:
		for body:RigidBody3D in group.get_meta("segment_bodies"):detached_safe=detached_safe and body.freeze
	check(detached_safe and living.detached_parts.size()==2,"existing and newly detached sibling groups obey suspension")
	living.set_simulation_available(true)
	for group:RigidBody3D in living.detached_parts:
		for body:RigidBody3D in group.get_meta("segment_bodies"):detached_safe=detached_safe and not body.freeze
	check(detached_safe,"all owned detached segments resume together")
	living.free();await process_frame
	var cancelled:=fresh();cancelled.begin_corpse_restore(0);await process_frame
	for attempt in 16:
		cancelled.prepare_corpse_step(1)
		if not cancelled._pending_pose_hull.is_empty():break
	check(not cancelled._pending_pose_hull.is_empty(),"cancellation fixture owns a worker hull task")
	cancelled.queue_free();await process_frame;await process_frame
	check(not is_instance_valid(cancelled),"partial admission retires without deferred activation or leaked nodes")
	var host:=preload("res://addons/player_runtime/corpse_loot.gd").new();stage.add_child(host)
	var coverage:=Coverage.new();stage.add_child(coverage);host.game=coverage
	var unavailable:=fresh();unavailable.begin_corpse_restore(0);await process_frame
	host.pending={"zombie":unavailable,"point":Vector3.ZERO};coverage.available=false
	host._advance_pending(Vector3.ZERO)
	check(host.pending.is_empty() and host.active.is_empty() and unavailable.is_queued_for_deletion(),"lost collision coverage cancels a pending corpse without publishing it")
	await process_frame
	var distant:=fresh();distant.begin_corpse_restore(0);await process_frame
	host.pending={"zombie":distant,"point":Vector3.ZERO};coverage.available=true
	host._advance_pending(Vector3(200,0,0))
	check(host.pending.is_empty() and host.active.is_empty() and distant.is_queued_for_deletion(),"leaving residency cancels pending work without adding an active corpse")
	await process_frame
	await staged_live_admission()
	stage.free();await process_frame
	print("ZOMBIE_RESIDENCY_LIFECYCLE checks=",checks," failures=",failures);quit(failures)
