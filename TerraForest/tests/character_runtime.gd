# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
var checks := 0
var ready_gate := true
var wet_gate := false
var stage: Node3D
var encounters: Node3D
var target: Node3D
var view: Node3D
var camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	stage = Node3D.new();root.add_child(stage)
	var ground := StaticBody3D.new();stage.add_child(ground)
	var collision := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(120,1,120);collision.shape=box;collision.position.y=-0.5;ground.add_child(collision)
	var floor_view := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(120,120);floor_view.mesh=plane;ground.add_child(floor_view)
	var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.light_energy=1.8;stage.add_child(light)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("364756");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.55;stage.add_child(environment)
	camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(0,1.68,0);camera.fov=75;camera.near=0.04;camera.current=true
	view=preload("res://addons/characters/runtime/human_view.gd").new();camera.add_child(view)
	check(view.clips.has_all(["FP_Place_Relaxed","FP_Pickaxe_Diagonal_Swing","FP_Pickaxe_SidePullback_Swing","FP_Pickaxe_Fresh_Idle","FP_Pickaxe_Fresh_Swing"]),"R11 retains placement and prior pickaxe actions beside the accepted fixed-grip library")
	check(view.meshes.size()>20,"R11 imported skinned body, wardrobe and equipment")
	print("HUMAN MESH NODES ",view.meshes.map(func(mesh):return mesh.name))
	view.equip(1);check(view.active_clip=="FP_Pickaxe_Fresh_Idle","pickaxe uses accepted fixed-grip idle")
	view.swing();check(view.active_clip=="FP_Pickaxe_Fresh_Swing" and is_equal_approx(view.action_remaining,1.7),"pickaxe uses accepted downward stroke and timing")
	view.equip(2);check(view.active_clip=="FP_Axe_Idle" and view.action_remaining==0.0,"switching tool cancels previous action")
	view.swing();check(view.active_clip=="FP_Axe_Swing","axe uses authored swing")
	view.equip(0);check(view.active_clip=="FP_Unarmed_Idle","empty hands remove equipped tools")
	for mesh in view.meshes:
		if String(mesh.name).to_lower().begins_with("equipment_"):check(not mesh.visible,"unarmed hides "+String(mesh.name))
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();stage.add_child(target);target.position=Vector3(0,0,5)
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters);encounters.enabled=true;encounters.target=target
	encounters.readiness=func(_bounds:AABB):return ready_gate
	encounters.water_depth=func(_point:Vector3):return 1.0 if wet_gate else 0.0
	await physics_frame;await physics_frame
	ready_gate=false;check(not encounters.supported_point(Vector3(0,0,-3)).is_finite(),"unloaded collision rejects spawn")
	ready_gate=true;wet_gate=true;check(not encounters.supported_point(Vector3(0,0,-3)).is_finite(),"underwater spawn rejects")
	wet_gate=false;check(not encounters.supported_point(Vector3(200,0,0)).is_finite(),"missing ground rejects spawn")
	var zombie=encounters.spawn_at(Vector3(0,0,-3))
	check(zombie!=null and zombie.initialized and zombie._r4_enabled,"R4 rig and behavior contract initialize")
	check(zombie.hit_areas.size()==14 and zombie.physical_bones.size()==15,"R4 installs fitted limb regions and ragdoll")
	check(zombie.collision_layer==1<<16,"zombie bodies use dedicated collision layer")
	for tick in 90:
		encounters.update(1.0/Engine.physics_ticks_per_second,Vector3.ZERO,true)
		await physics_frame
	check(zombie.position.z > -2.9,"zombie pursues the real target with physical movement")
	encounters.update(0.01,Vector3.ZERO,false)
	check(zombie.process_mode==Node.PROCESS_MODE_DISABLED,"world updates suspend zombie subtree")
	var paused:Vector3=zombie.position
	for tick in 5:await physics_frame
	check(zombie.position.is_equal_approx(paused),"suspended zombie does not move")
	encounters.update(0.01,Vector3.ZERO,true)
	check(zombie.process_mode==Node.PROCESS_MODE_INHERIT,"ready world resumes zombie")
	zombie.set_behavior(false);zombie.set_physics_process(false)
	var chest:Vector3=zombie.global_position+Vector3.UP
	var hit:Dictionary=encounters.pick(chest+Vector3(0,0,2),chest-Vector3(0,0,2),[])
	check(hit.get("kind")=="zombie","melee ray resolves fitted zombie target")
	check(encounters.apply_hit(hit,20.0,Vector3.FORWARD),"melee delivers damage to zombie controller")
	check(zombie.health<180.0,"damage changes live zombie health")
	# Insert a wall ahead of the zombie: picking must respect solid-world occlusion.
	var wall:=StaticBody3D.new();stage.add_child(wall);var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(2,3,0.15);wall_shape.shape=wall_box;wall.add_child(wall_shape);wall.position=chest+Vector3(0,0,1)
	await physics_frame;await physics_frame
	check(encounters.pick(chest+Vector3(0,0,2),chest-Vector3(0,0,2),[]).is_empty(),"solid wall blocks zombie melee ray")
	wall.free()
	zombie.set_physics_process(true)
	target.position=zombie.global_position+Vector3(0,0,0.65)
	zombie.set_behavior(true)
	for tick in 220:
		encounters.update(1.0/Engine.physics_ticks_per_second,target.global_position,true)
		await physics_frame
	check(target.damage_received>0.0,"animated zombie contacts reach player target adapter")
	zombie.set_behavior(false);zombie.set_physics_process(false)
	zombie.receive_hit("shin_l",100.0,chest,Vector3.ZERO)
	check(zombie.alive and zombie.missing.shin_l and (zombie._crawling or zombie._crawl_transition),"leg loss keeps R4 alive and enters crawl")
	zombie.die();check(not zombie.alive,"fatal damage starts corpse ragdoll")
	encounters.update(21.0,Vector3.ZERO,false)
	check(not encounters.residents.has(zombie),"corpses retire within the encounter budget")
	await process_frame
	encounters.clear();await process_frame
	for index in 8:encounters.spawn_at(Vector3(float(index)*2-7,0,-5))
	check(encounters.residents.size()==6,"live encounter population never exceeds six")
	encounters.clear();await process_frame
	encounters._spawn_clock=0;encounters.update(0.1,Vector3.ZERO,true)
	check(encounters.residents.size()==1,"automatic scheduler admits one supported encounter")
	ready_gate=false;encounters.update(0.1,Vector3.ZERO,true)
	check(encounters.residents.size()==1 and encounters.residents[0].process_mode==Node.PROCESS_MODE_DISABLED,"unknown streamed collision holds resident without deleting it")
	ready_gate=true
	# Capture actual FP crop and a full R4 zombie together for visual review.
	encounters.clear();await process_frame
	target.position=Vector3(0,0,4)
	var subject=encounters.spawn_at(Vector3(0,0,-3.5));subject.set_behavior(false);subject.rotation.y=0
	view.equip(1)
	for tick in 8:await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports/character_runtime")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/character_runtime/pickaxe.png")
		view.swing()
		for tick in 30:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/character_runtime/pickaxe_swing.png")
		view.equip(2)
		for tick in 8:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/character_runtime/axe.png")
	var report:=FileAccess.open("res://reports/character_runtime/result.json",FileAccess.WRITE);report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));report.close()
	encounters.clear();await process_frame
	stage.free();await process_frame
	print("CHARACTER_RUNTIME_OK" if failures==0 else "CHARACTER_RUNTIME_FAIL")
	quit(0 if failures==0 else 1)
