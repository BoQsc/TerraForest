# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks := 0
var failures := 0
var stage: Node3D
var encounters: Node3D
var target: Node3D
var player: CharacterBody3D
var available := true
var driving_updates := false
var starts := 0
var finishes := 0
var maximum_action_time := 0.0
var minimum_spacing := INF
var camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	run.call_deferred()

func _tick_encounters() -> void:
	if not driving_updates: return
	encounters.update(1.0 / Engine.physics_ticks_per_second, player.global_position, available)
	for zombie in encounters.residents:
		maximum_action_time = maxf(maximum_action_time, zombie.get_behavior_snapshot().action_time)
	for a in encounters.residents.size():
		for b in range(a + 1, encounters.residents.size()):
			var offset: Vector3 = encounters.residents[a].position - encounters.residents[b].position
			minimum_spacing = minf(minimum_spacing, Vector2(offset.x, offset.z).length())

func run() -> void:
	stage = Node3D.new();root.add_child(stage)
	var ground := StaticBody3D.new();stage.add_child(ground)
	var collider := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(80,1,80);collider.shape=box;collider.position.y=-0.5;ground.add_child(collider)
	var floor_view := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(80,80);floor_view.mesh=plane;var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color("53614d");plane.material=floor_material;ground.add_child(floor_view)
	var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-20,0);light.light_energy=1.7;light.shadow_enabled=true;stage.add_child(light)
	var world := WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("354a60");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.55;stage.add_child(world)
	player=CharacterBody3D.new();player.collision_layer=2;player.collision_mask=1|(1<<16);stage.add_child(player)
	var player_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.34;capsule.height=1.8;player_shape.shape=capsule;player_shape.position.y=0.9;player.add_child(player_shape)
	var player_view:=MeshInstance3D.new();var capsule_mesh:=CapsuleMesh.new();capsule_mesh.radius=0.34;capsule_mesh.height=1.8;player_view.mesh=capsule_mesh;player_view.position.y=0.9;var target_material:=StandardMaterial3D.new();target_material.albedo_color=Color(0.15,0.7,0.9,0.4);target_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;capsule_mesh.material=target_material;player.add_child(player_view)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(3,2.8,-3.6);camera.look_at(Vector3(0,0.9,-0.4));camera.current=true
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters);encounters.enabled=true;encounters.target=target
	encounters.readiness=func(_bounds:AABB):return true
	encounters._spawn_clock=100000.0
	physics_frame.connect(_tick_encounters)
	await physics_frame;await physics_frame
	# All six approach from the same side, including two initially queued behind peers.
	for point in [Vector3(0,0,-1.1),Vector3(0.04,0,-2.3),Vector3(-1.6,0,-1.7),Vector3(1.6,0,-1.7),Vector3(-1.0,0,-3.4),Vector3(1.0,0,-3.4)]:
		var zombie=encounters.spawn_at(point)
		check(zombie!=null,"crowd fixture admits supported zombie")
		if zombie!=null:
			zombie.attack_started.connect(func(_action:String):starts+=1)
			zombie.action_finished.connect(func(_action:String):finishes+=1)
	driving_updates=true
	for tick in Engine.physics_ticks_per_second*12:await physics_frame
	check(maximum_action_time>0.5,"per-tick encounter updates let attack windups reach contact")
	check(finishes>0,"autonomous attacks finish through manager updates")
	check(target.damage_received>0,"crowd attacks actually reach player damage adapter")
	check(minimum_spacing>=0.45,"zombie movement capsules never interpenetrate")
	var attackers:=0
	var rows:Array=[]
	for zombie in encounters.residents:
		var state:Dictionary=zombie.get_behavior_snapshot()
		if state.contact_count>0:attackers+=1
		rows.append(state)
	check(attackers>=3,"queued zombies spread around peers and join melee")
	var player_clear:=true
	for zombie in encounters.residents:
		var offset:Vector3=zombie.global_position-player.global_position
		player_clear=player_clear and Vector2(offset.x,offset.z).length()>=0.55
	check(player_clear,"zombies stop at player capsule instead of entering it")
	available=false
	for tick in 5:await physics_frame
	var damage_before:float=target.damage_received
	for tick in Engine.physics_ticks_per_second:await physics_frame
	check(is_equal_approx(damage_before,target.damage_received),"paused encounters cannot land strikes")
	available=true
	for tick in Engine.physics_ticks_per_second*4:await physics_frame
	check(target.damage_received>damage_before,"resuming encounters restores completed attack contacts")
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_encounters")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/zombie_encounters/crowd.png")
	# Solid player collision must not strand the source's living crawl behavior.
	driving_updates=false;encounters.clear();await process_frame;await physics_frame
	encounters._spawn_clock=100000.0
	var crawler=encounters.spawn_at(Vector3(0,0,-1.2))
	var crawler_state:Dictionary={}
	check(crawler!=null,"leg-loss fixture admits supported zombie")
	if crawler!=null:
		var before_crawl:float=target.damage_received
		crawler.receive_hit("shin_l",100.0,crawler.position,Vector3.ZERO)
		driving_updates=true
		for tick in Engine.physics_ticks_per_second*7:await physics_frame
		check(crawler.alive and crawler.get_behavior_snapshot().crawling,"manager ticks preserve living crawl transition")
		check(target.damage_received>before_crawl and crawler.get_behavior_snapshot().contact_count>0,"crawler can bite a solid player without walking through its capsule")
		crawler_state=crawler.get_behavior_snapshot()
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/zombie_encounters/crawl.png")
	var report:=FileAccess.open("res://reports/zombie_encounters/result.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"attack_starts":starts,"attack_finishes":finishes,"maximum_action_time":maximum_action_time,"minimum_spacing":minimum_spacing,"attacking_zombies":attackers,"damage_received":target.damage_received,"residents":rows,"crawler":crawler_state},"  "));report.close()
	driving_updates=false;encounters.clear();await process_frame
	stage.free();await process_frame
	print("ZOMBIE_ENCOUNTERS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
