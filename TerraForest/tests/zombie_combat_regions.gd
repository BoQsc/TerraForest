# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var checks:=0
var failures:=0
var stage:Node3D
var encounters:Node3D
var camera:Camera3D
var folder:="res://reports/zombie_combat_regions"
var trace:Array=[]
var fragment_anatomy:RefCounted
func _tick_fragments()->void:
	if fragment_anatomy!=null:fragment_anatomy.advance_ragdolls(1.0/Engine.physics_ticks_per_second)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	physics_frame.connect(_tick_fragments)
	run.call_deferred()
func ticks(count:int)->void:
	for i in count:await physics_frame
func fresh()->Node3D:
	encounters.clear();await ticks(2)
	var zombie:Node3D=encounters.spawn_at(Vector3.ZERO)
	if zombie!=null:zombie.set_behavior(false)
	return zombie
func capture(label:String,zombie:Node3D)->void:
	if DisplayServer.get_name()=="headless":return
	camera.global_position=zombie.global_position+Vector3(2,1.7,2.4);camera.look_at(zombie.global_position+Vector3.UP*.75)
	await ticks(12)
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func surface_shot(zombie:Node3D,part:String,visible_to_world:bool=false)->Dictionary:
	# Independent CPU skin baking is the reference for the native query's live pose.
	var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes[part],Transform3D.IDENTITY)
	var candidates:Array=[]
	for surface in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count:int=indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0,count-2,3):
			var a:Vector3=vertices[indices[i] if not indices.is_empty() else i]
			var b:Vector3=vertices[indices[i+1] if not indices.is_empty() else i+1]
			var c:Vector3=vertices[indices[i+2] if not indices.is_empty() else i+2]
			var normal:Vector3=(b-a).cross(c-a)
			candidates.append({"area":normal.length_squared(),"normal":normal.normalized(),"point":(a+b+c)/3})
	# A lying head can have its largest facial triangles against the floor.
	# Probe its exposed upper surface for postmortem targeting.
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return a.point.y>b.point.y if visible_to_world else a.area>b.area)
	for i in mini(24,candidates.size()):
		var triangle:Dictionary=candidates[i];var start:Vector3=triangle.point+triangle.normal*.035;var end:Vector3=triangle.point-triangle.normal*.035
		var hit:Dictionary=zombie.anatomy.pick(start,end)
		if hit.get("part","")==part and hit.position.distance_to(triangle.point)<.001:
			if visible_to_world and encounters.pick(start,end,[]).get("part","")!=part:continue
			return {"start":start,"end":end,"hit":hit}
	return {}
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zombie-combat-dir="):folder=arg.trim_prefix("--zombie-combat-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	stage=Node3D.new();root.add_child(stage)
	var floor:=StaticBody3D.new();floor.collision_layer=2;stage.add_child(floor)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(80,1,80);collision.shape=box;collision.position.y=-.5;floor.add_child(collision)
	# Admission uses terrain mask 1; the settled corpse must also recognize model mask 2.
	floor.collision_layer=3
	var visual:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);visual.mesh=plane;floor.add_child(visual)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.4;stage.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("354650");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;stage.add_child(env)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	var target:=Node3D.new();stage.add_child(target);target.position=Vector3(0,0,60)
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters);encounters.enabled=true;encounters.target=target;encounters.readiness=func(_bounds:AABB):return true
	await ticks(3)
	var zombie:Node3D=await fresh()
	if zombie==null:check(false,"zombie fixture admits");stage.free();quit(1);return
	check(zombie.anatomy.snapshot().triangles>1000 and zombie.anatomy.snapshot().vertices<131072,"native geometry caches the supplied rig within declared limits")
	var tested:Dictionary={}
	for pose in [["Zombie_Idle",.3],["Zombie_Attack_Both",.7],["Zombie_Walk_Drag_Right",.6],["Zombie_Crawl",.8],["Zombie_Attack_Bite",.6],["Zombie_Crawl_Bite",.5]]:
		zombie.play_clip(pose[0]);zombie.animation_player.pause();zombie.animation_player.seek(pose[1],true);zombie.skeleton.force_update_all_bone_transforms()
		var hits:=0
		for part:String in Zombie.PARTS:
			var shot:Dictionary=surface_shot(zombie,part)
			if not shot.is_empty():hits+=1;tested[part]=true
		check(hits>=12,"native damage surfaces follow independently baked skin during "+str(pose[0])+" (%d regions)"%hits)
	check(tested.size()==14,"all fourteen damage regions are reachable at their visible animated surface")
	zombie.play_clip("Zombie_Idle");zombie.animation_player.pause();zombie.animation_player.seek(.0,true);await ticks(2)
	check(encounters.pick(Vector3(0,.3,1),Vector3(0,.3,-1),[]).is_empty(),"air between the legs does not hit the movement capsule or a broad limb hull")
	var torso_shot:=surface_shot(zombie,"torso")
	check(not torso_shot.is_empty() and encounters.pick(torso_shot.start,torso_shot.end,[]).get("part")=="torso","world combat uses the same evaluated surface picker")
	var original:float=zombie.health
	zombie.receive_hit("forearm_l",20)
	check(zombie.health==original-20 and zombie.limb_health.forearm_l==32 and zombie._arm_condition("l")<1,"a light forearm wound applies full shared damage with limited limb trauma")
	zombie.receive_hit("forearm_l",36,Vector3.ZERO,Vector3.ZERO,false,"heavy")
	check(zombie.alive and zombie.missing.forearm_l and zombie.missing.hand_l and zombie.health==original-56,"a heavy forearm strike damages shared health and detaches its hand")
	check(not "left" in zombie.get_available_attacks() and not "both" in zombie.get_available_attacks() and "right" in zombie.get_available_attacks(),"lost arm chain removes only anatomically impossible attacks")
	await capture("arm_detachment",zombie)
	# Exercise every sever root through the actual controller, including caps and colliders.
	for part:String in Zombie.PARTS:
		if part=="torso":continue
		zombie=await fresh();zombie.sever_limb(part)
		var native:Dictionary=zombie.anatomy.snapshot()
		var correct:bool=zombie.missing[part] and native.missing[part] and not zombie.part_meshes[part].visible and zombie.hit_areas[part].collision_layer==0 and zombie.detached_parts.size()==1 and zombie.caps[part].body.visible
		if part=="head":correct=correct and not zombie.alive and zombie.health==0
		elif part.begins_with("thigh") or part.begins_with("shin") or part.begins_with("foot"):correct=correct and zombie.alive and (zombie._crawl_transition or zombie._crawling)
		check(correct,"complete sever behavior for "+part)
	zombie=await fresh();zombie.sever_limb("thigh_l");await ticks(65)
	check(zombie.alive and zombie._crawling and zombie.get_crawl_speed()>0 and not zombie.request_jump(),"leg loss produces living crawl and disables unsupported jumping")
	zombie.sever_limb("upper_arm_l");var one_arm:float=zombie.get_crawl_speed();zombie.sever_limb("upper_arm_r")
	check(one_arm>0 and zombie.get_crawl_speed()==0 and "crawl_bite" in zombie.get_available_attacks(),"one arm slows crawling; no arms leaves an anatomically valid stationary bite")
	await capture("crawl_limbs",zombie)
	zombie=await fresh();zombie.position.y=10;zombie.die();await ticks(60)
	check(zombie.anatomy.ragdoll_stats().sleeping==0 and zombie.physical_bones.Hips.linear_velocity.y<-.5,"an airborne ragdoll keeps falling and is never frozen by a timeout")
	# Start close to the ground and allow genuine contact/settling on a model floor.
	zombie=await fresh();floor.collision_layer=2;zombie.position.y=1;zombie.die(Vector3(1,0,0))
	for second in 10:
		await ticks(60);trace.append({"second":second+1,"rig":zombie.anatomy.ragdoll_stats(),"hips":str(zombie.physical_bones.Hips.global_position)})
	var stats:Dictionary=zombie.anatomy.ragdoll_stats();print("RAGDOLL_SETTLE ",JSON.stringify(trace))
	check(stats.bodies>0 and stats.sleeping==stats.bodies,"grounded corpse settles with every physical body asleep")
	check(zombie.physical_bones.Hips.global_position.y>-.2,"corpse collides with structure/model floor layer 2")
	zombie.set_behavior(true)
	check(not zombie.behavior_enabled and not zombie.animation_player.active and zombie.health==0,"host updates cannot reactivate a corpse animation or behavior motor")
	var drives_off:=true
	for body:PhysicalBone3D in zombie.physical_bones.values():
		for row:Dictionary in body.get_property_list():
			if (str(row.name).contains("spring") or str(row.name).contains("motor")) and str(row.name).ends_with("enabled") and body.get(row.name):drives_off=false
	check(drives_off,"corpse joints have no spring or motor drives")
	await capture("settled_corpse",zombie)
	# A knocked/sliding corpse is no longer near its old CharacterBody root.
	for body:PhysicalBone3D in zombie.physical_bones.values():body.global_position+=Vector3(8,0,0)
	await ticks(3)
	var corpse_shot:=surface_shot(zombie,"head",true)
	check(not corpse_shot.is_empty() and encounters.pick(corpse_shot.start,corpse_shot.end,[]).get("part")=="head","corpse displaced from its character root retains accurate postmortem targeting")
	if not corpse_shot.is_empty():
		var hit:Dictionary=corpse_shot.hit;hit.zombie=zombie
		check(encounters.apply_hit(hit,50,Vector3.UP,"firearm") and zombie.missing.head and not zombie.alive,"firearm combat adapter can detach a corpse head without reviving it")
		await ticks(2)
		check(zombie.anatomy.ragdoll_stats().sleeping<zombie.anatomy.ragdoll_stats().bodies,"new impact wakes physical pieces after settling")
	var before_drop:float=zombie.physical_bones.Hips.global_position.y
	floor.position.y=-3
	await ticks(45)
	check(zombie.physical_bones.Hips.global_position.y<before_drop-.2,"removing resting support restores gravity instead of leaving a frozen corpse in the air")
	# Separated fragments must not starve behind a shared support-ray budget.
	floor.position.y=0
	fragment_anatomy=ClassDB.instantiate("NativeZombieAnatomy");fragment_anatomy.configure(Zombie.PARTS)
	var scattered:Array[RigidBody3D]=[]
	for i in 6:
		var part:RigidBody3D=ClassDB.instantiate("NativeZombieRigidPart");part.position=Vector3(-12+i*3,.3,6);part.collision_layer=1<<18;part.collision_mask=2;part.continuous_cd=true;stage.add_child(part)
		var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.2;shape.shape=sphere;part.add_child(shape)
		var bodies:Array[PhysicsBody3D]=[part];fragment_anatomy.track_ragdoll(bodies)
		scattered.append(part)
	await ticks(120)
	# These unconstrained spheres can naturally sleep before the .9s quiet timer.
	# Seed the same rest flag as parked fragments, then verify ongoing support.
	for part:RigidBody3D in scattered:part.set_resting(true);part.sleeping=true
	await ticks(120)
	var fragments:Dictionary=fragment_anatomy.ragdoll_stats()
	print("SCATTERED_FRAGMENTS ",JSON.stringify(fragments))
	var swept_off:=true
	for part:RigidBody3D in scattered:if part.continuous_cd or not part.custom_integrator:swept_off=false
	check(fragments.groups==6 and fragments.resting==6 and fragments.sleeping==6 and swept_off,"six scattered detached islands all retain verified physical rest with CCD parked")
	floor.position.y=-3
	await ticks(45)
	var swept_on:=true
	for part:RigidBody3D in scattered:if not part.continuous_cd or part.custom_integrator or part.position.y>=0:swept_on=false
	check(swept_on and fragment_anatomy.ragdoll_stats().resting==0,"losing fragment support restores gravity, falling and original swept collision settings")
	fragment_anatomy=null
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"trace":trace},"  "))
	encounters.clear();await process_frame;stage.free();await process_frame
	print("ZOMBIE_COMBAT_REGIONS checks=",checks," failures=",failures);quit(1 if failures else 0)
