extends SceneTree

const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var failures:=0
var checks:=0
var anatomy:RefCounted
var body:RigidBody3D
var contact_sample:Dictionary={}
var output:=""
var samples:Array=[]

func check(passed:bool,label:String)->void:
	checks+=1
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1

func tick()->void:
	if anatomy!=null:anatomy.advance_ragdolls(1.0/Engine.physics_ticks_per_second)
	if body!=null and contact_sample.is_empty():
		var state:=PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state!=null and state.get_contact_count()>0:
			contact_sample={"body":str(state.transform.origin),"local":str(state.get_contact_local_position(0)),"collider":str(state.get_contact_collider_position(0)),"normal":str(state.get_contact_local_normal(0))}

func ticks(count:int)->void:
	for frame in count:await physics_frame

func _initialize()->void:
	physics_frame.connect(tick);run.call_deferred()

func stack_case()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var floor:=StaticBody3D.new();floor.position=Vector3(950,34.5,1130);stage.add_child(floor)
	var slab:=BoxShape3D.new();slab.size=Vector3(10,1,10);var support:=CollisionShape3D.new();support.shape=slab;floor.add_child(support)
	var owners:Array[RefCounted]=[];var pieces:Array[RigidBody3D]=[]
	for index in 3:
		var part:RigidBody3D=ClassDB.instantiate("NativeZombieRigidPart");part.position=Vector3(950,35.2+index*.3,1130);part.collision_layer=Zombie.RAGDOLL_LAYER;part.collision_mask=1|Zombie.RAGDOLL_LAYER;part.continuous_cd=true;part.can_sleep=false;stage.add_child(part)
		var shape:=BoxShape3D.new();shape.size=Vector3(.8,.2,.8);var collision:=CollisionShape3D.new();collision.shape=shape;part.add_child(collision)
		var owner:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");owner.configure(Zombie.PARTS);var members:Array[PhysicsBody3D]=[part];owner.track_ragdoll(members);owners.append(owner);pieces.append(part)
	anatomy=owners[0];await ticks(180)
	var native_events:Array=[]
	for owner:RefCounted in owners:native_events.append(owner.ragdoll_stats())
	for part:RigidBody3D in pieces:part.can_sleep=true
	await ticks(120)
	var parked:=0;var initial:Array[float]=[];var parked_states:Array=[]
	for index in pieces.size():
		var stats:Dictionary=owners[index].ragdoll_stats();parked_states.append(stats)
		if stats.resting==1 and stats.sleeping==1 and stats.settle_events>0:parked+=1
		initial.append(pieces[index].global_position.y)
	check(parked==3,"contact island spans three independent anatomy owners")
	floor.position.y-=.12;await ticks(120)
	var moved:=0
	for index in pieces.size():
		if absf(initial[index]-pieces[index].global_position.y-.12)<.025:moved+=1
	check(moved==3,"withdrawing the bottom support releases the complete stack")
	samples.append({"shape":"three_owner_stack","parked":parked,"moved":moved,"native_events":native_events,"parked_states":parked_states})
	pieces[2].queue_free();await ticks(3)
	check(owners[2].ragdoll_stats().groups==0,"freed contact groups retire without retaining stale bodies")
	anatomy=null;stage.free();owners.clear();pieces.clear();await ticks(3)

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ragdoll-evidence="):output=argument.trim_prefix("--ragdoll-evidence=")
	for kind in ["sphere","box","capsule","rotated_body"]:
		var stage:=Node3D.new();root.add_child(stage)
		var floor:=StaticBody3D.new();stage.add_child(floor);floor.position=Vector3(950,34.5,1130);floor.collision_layer=1
		var support:=CollisionShape3D.new();var slab:=BoxShape3D.new();slab.size=Vector3(10,1,10);support.shape=slab;floor.add_child(support)
		body=ClassDB.instantiate("NativeZombieRigidPart");body.position=Vector3(950,35.8,1130);body.collision_layer=Zombie.RAGDOLL_LAYER;body.collision_mask=7|Zombie.RAGDOLL_LAYER;body.continuous_cd=true;stage.add_child(body)
		var collision:=CollisionShape3D.new()
		if kind=="sphere":
			var shape:=SphereShape3D.new();shape.radius=.2;collision.shape=shape
		elif kind=="box":
			var shape:=BoxShape3D.new();shape.size=Vector3(.4,.2,.6);collision.shape=shape
		else:
			var shape:=CapsuleShape3D.new();shape.radius=.08;shape.height=.6;collision.shape=shape
			if kind=="rotated_body":body.rotation.z=deg_to_rad(70)
			else:collision.rotation.z=deg_to_rad(70)
		body.add_child(collision)
		var original_linear:float=PhysicsServer3D.body_get_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_LINEAR_DAMP)
		var original_angular:float=PhysicsServer3D.body_get_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP)
		anatomy=ClassDB.instantiate("NativeZombieAnatomy");anatomy.configure(Zombie.PARTS)
		var bodies:Array[PhysicsBody3D]=[body];check(anatomy.track_ragdoll(bodies),"native part tracked: "+kind)
		contact_sample={};await ticks(240)
		var initial:float=body.global_position.y
		check(anatomy.ragdoll_stats().sleeping==1,"part initially sleeps: "+kind)
		floor.position.y-=.12
		await ticks(90)
		var lowered:float=body.global_position.y
		check(initial-lowered>.08,"small support withdrawal restores gravity: "+kind)
		check(absf((initial-lowered)-.12)<.025,"part settles on slightly lowered support: "+kind)
		samples.append({"shape":kind,"initial_y":initial,"lowered_y":lowered,"drop":initial-lowered,"contact":contact_sample,"stats":anatomy.ragdoll_stats()})
		print("REST_SUPPORT ",JSON.stringify(samples.back()))
		floor.position.y-=3;await ticks(12)
		check(not body.is_resting() and body.linear_velocity.y<-.5,"unsupported part is not parked by a timeout: "+kind)
		check(body.continuous_cd and not body.custom_integrator,"support loss restores swept collision and gravity: "+kind)
		check(is_equal_approx(float(PhysicsServer3D.body_get_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_LINEAR_DAMP)),original_linear) and is_equal_approx(float(PhysicsServer3D.body_get_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP)),original_angular),"support loss restores original airborne damping: "+kind)
		body=null;anatomy=null;stage.free();await ticks(2)
	await stack_case()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"  "))
	print("ZOMBIE_REST_SUPPORT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
