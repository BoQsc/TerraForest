# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var game:Node
var photographed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func box(at:Vector3,size:Vector3,color:Color)->void:
	var body:=StaticBody3D.new();body.position=at;game.add_child(body)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;var material:=StandardMaterial3D.new();material.albedo_color=color;mesh.material=material;view.mesh=mesh;body.add_child(view)
func photograph()->void:
	if photographed or DisplayServer.get_name()=="headless":return
	photographed=true;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/zombie_door_interaction/attack.png")
func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	game.zombies.force_pursuit=true # Door accounting fixture begins with an acquired target.
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual host world becomes ready")
	if not game.loading_active:
		game._clear_motion();game.needs_floor_spawn=false;game.fly=false;game.app_focused=true
		if game.session_menu.developer:game.session_menu.toggle_developer()
		game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		game.zombies.clear();await physics_frame;game.zombies._spawn_clock=100000.0
		var centre:Vector3=game.player.global_position+Vector3.UP*6
		box(centre-Vector3.UP*.5,Vector3(14,1,14),Color("6f7569"))
		box(centre+Vector3(0,1.5,-2.75),Vector3(.25,3,4.5),Color("9b8868"))
		box(centre+Vector3(0,1.5,2.75),Vector3(.25,3,4.5),Color("9b8868"))
		game.player.global_position=centre+Vector3(2.5,.06,0);game.terrain.focus=game.player.global_position
		var batch:Node3D=game.doors.collection
		var identity:=900001
		var pose:=PackedFloat32Array([0,0,1,centre.x,0,1,0,centre.y,-1,0,0,centre.z+.5])
		check(batch.upsert_instances(PackedInt64Array([identity]),pose),"real breakable wooden door inserted into host model collection")
		batch.set_collision_focus(centre)
		for tick in 30:await physics_frame;game.app_focused=true
		var zombie:CharacterBody3D=game.zombies.spawn_at(centre+Vector3(-2.5,.06,0))
		check(zombie!=null,"zombie admits in loaded test entrance")
		var inventory_before:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
		var hinge_before:PackedByteArray=game.doors.state.capture_storage_snapshot()
		var durability_before:PackedByteArray=game.world_attack.durability.capture_storage_snapshot()
		var marked_damage:=false
		var context_seen:=false
		var minimum_door_side:=INF
		DirAccess.make_dir_recursive_absolute("res://reports/zombie_door_interaction")
		var camera:=Camera3D.new();game.add_child(camera);camera.position=centre+Vector3(-4,3,4);camera.look_at(centre+Vector3.UP);camera.current=true;game.tool_view.human.hide()
		if zombie!=null:
			for tick in Engine.physics_ticks_per_second*28:
				await physics_frame;game.app_focused=true
				if not is_instance_valid(zombie):break
				if game.zombies._obstacles.has(zombie.get_instance_id()):context_seen=true
				if not batch.get_instance(identity).is_empty():
					minimum_door_side=minf(minimum_door_side,centre.x-zombie.global_position.x)
					marked_damage=marked_damage or game.world_attack.durability.capture_storage_snapshot()!=durability_before
					if zombie._action_time>.4:photograph()
				else:break
			check(context_seen,"blocked-door perception selects explicit breakable interaction target")
			check(marked_damage,"authored attack contacts debit existing world durability")
			check(batch.get_instance(identity).is_empty(),"repeated validated attacks destroy actual wooden door")
			check(minimum_door_side>.20,"zombie cannot walk through the intact door")
			check(is_instance_valid(zombie) and game.zombies.residents.has(zombie),"door collision refresh holds rather than deleting attacking zombie")
			for tick in Engine.physics_ticks_per_second*10:
				await physics_frame;game.app_focused=true
				if game.zombie_target.damage_received>0:break
			check(game.zombie_target.damage_received>0,"door removal invalidates route and zombie reaches player")
		check(game.player_hud.inventory.capture_storage_snapshot()==inventory_before,"NPC destruction grants no player salvage and consumes no tool wear")
		check(game.doors.state.capture_storage_snapshot()==hinge_before,"door destruction leaves no orphan hinge state")
		check(game.terrain.changed_since_save,"door damage/removal marks compound world dirty")
		var snapshot:PackedByteArray=batch.capture_snapshot()
		check(batch.validate_snapshot(snapshot) and batch.restore_snapshot(snapshot) and batch.get_instance(identity).is_empty(),"model snapshot round trip preserves destroyed door")
		check(game.persistence._capture().sections.has("world_durability"),"existing world component captures NPC structural damage")
		if DisplayServer.get_name()!="headless":
			camera.position=centre+Vector3(-1.5,4,0);camera.look_at(centre+Vector3(1,0.6,0))
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/zombie_door_interaction/after.png")
		var report:=FileAccess.open("res://reports/zombie_door_interaction/result.json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"minimum_intact_door_side":minimum_door_side,"player_damage":game.zombie_target.damage_received,"context_seen":context_seen,"durability_changed":marked_damage,"door_removed":batch.get_instance(identity).is_empty(),"zombie":zombie.get_behavior_snapshot() if is_instance_valid(zombie) else {},"navigation":game.zombies.navigation_status},"  "));report.close()
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_DOOR_INTERACTION checks=",checks," failures=",failures);quit(0 if failures==0 else 1)
