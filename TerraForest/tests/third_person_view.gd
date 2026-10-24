# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var evidence:="res://reports/third_person_view"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func ticks(count:int)->void:
	for i in count:await physics_frame
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--third-person-evidence="):evidence=argument.trim_prefix("--third-person-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.player_view.settings_path="" # Never change the user's camera preference.
	root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"playable forest and player ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	game.player_hud.equip_item(2)
	var view=game.player_view;var human=game.tool_view.human
	check(not view.enabled and not view.active and game.camera.current,"first person remains the default")
	var eye_pose:Transform3D=game.camera.transform
	var feet:Vector3=game.player.global_position
	game.session_menu.set_open(true)
	var toggle:CheckButton=game.session_menu.third_person_toggle
	check(toggle.visible and toggle.text.contains("Third-person"),"ESC Session exposes the optional third-person checkbox")
	toggle.button_pressed=true
	check(view.enabled and view.active and view.third_camera.current and game.session_menu.opened,"checkbox switches the actual viewport camera while leaving ESC open")
	game.session_menu.set_open(false);await ticks(4);view.update()
	check(game.camera.transform.is_equal_approx(eye_pose) and game.player.global_position==feet,"view switching preserves the existing eye aim and player body")
	check(human.third_person and human.global_position.distance_to(feet)<.01 and absf(human.global_basis.y.dot(Vector3.UP)-1)<.001,"one full player model stands upright at the feet")
	var face_visible:bool=not human.face_surfaces.is_empty()
	for entry:Array in human.face_surfaces:if entry[0].get_surface_override_material(entry[1])!=null:face_visible=false
	check(face_visible,"third person restores the supplied model's head surfaces")
	check(game.vegetation.camera==view.third_camera and game.ecosystem.camera==view.third_camera and game.water_camera.camera==view.third_camera,"visibility and underwater presentation use the actual render camera")
	await capture("third_person_forest")
	# Keep the original eye ray/reach while aiming at a known nearby object.
	var target:=StaticBody3D.new();target.collision_layer=2;game.add_child(target)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.6,.6,.6);shape.shape=box;target.add_child(shape)
	target.global_position=game.camera.global_position-game.camera.global_basis.z*2.5
	await ticks(3);view.update()
	var hit:Dictionary=game.structures.blocks.raycast_scene(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.5,7,[game.player.get_rid()])
	var projected:Vector2=view.third_camera.unproject_position(hit.position) if not hit.is_empty() else Vector2.INF
	check(hit.get("collider")==target and projected.distance_to(Vector2(root.size)*.5)<2.0,"render-camera centre agrees with the unchanged eye target")
	target.free()
	# A solid obstacle behind the player must shorten the native boom.
	var wall:=StaticBody3D.new();wall.collision_layer=2;game.add_child(wall)
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(4,4,.2);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	wall.global_transform=Transform3D(game.camera.global_basis,game.camera.global_position+game.camera.global_basis.z*1.3)
	await ticks(4);view.update()
	check(view.arm.get_hit_length()<1.4 and view.third_camera.global_position.distance_to(game.camera.global_position)<1.7,"native spring arm retracts before a wall behind the player")
	await capture("collision_retraction")
	wall.global_transform=Transform3D(game.camera.global_basis*Basis(Vector3.UP,PI*.5),game.camera.global_position+game.camera.global_basis.x*.5)
	await ticks(4);view.update()
	check(view.arm.get_hit_length()<2.0,"shoulder sweep also retracts before a thin wall beside the player")
	wall.global_basis=game.camera.global_basis
	wall.global_position=game.camera.global_position+game.camera.global_basis.z*.5
	await ticks(4);view.update()
	check(view.arm.get_hit_length()<.8 and (view.third_camera.cull_mask&view.PLAYER_LAYER)==0 and game.tool_view.is_visible_in_tree(),"very close obstacles hide body geometry without disabling held-tool actions")
	var contacts:Array=[];game.tool_view.attack_contact.connect(func(identity:int):contacts.append(identity))
	# Automation may have yielded OS focus to Codex while capturing the view.
	# Exercise the foreground input contract explicitly, as the vehicle fixture does.
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.world_attack.next_attack=0
	print("ATTACK_VIEW_INPUT ",JSON.stringify({"focused":game.app_focused,"mouse":Input.mouse_mode,"admitted":game._model_edit_available(),"pending":game.world_attack.pending,"item":game.equipped_tool,"action_remaining":human.action_remaining}))
	check(game.world_attack.attack(),"held-tool attack starts in third person with a retracted camera")
	check(await wait_for(func():return game.world_attack.pending.is_empty(),4) and contacts.size()==1,"third-person swing preserves its single authored animation contact")
	wall.free();await ticks(4)
	game.session_menu.set_open(true);toggle.button_pressed=false
	check(not view.active and game.camera.current and game.tool_view.transform.is_equal_approx(Transform3D.IDENTITY) and not human.third_person,"unchecking restores first-person camera and tool transforms")
	var face_hidden:=true
	for entry:Array in human.face_surfaces:if entry[0].get_surface_override_material(entry[1])!=entry[2]:face_hidden=false
	check(face_hidden,"returning to first person reinstates hidden head surfaces")
	await capture("esc_toggle")
	# The setting persists separately from world saves; use an isolated test path.
	var path:="user://third_person_check_%d.cfg"%OS.get_process_id()
	view.settings_path=path;view.set_enabled(true)
	var config:=ConfigFile.new()
	check(config.load(path)==OK and config.get_value("camera","third_person",false),"camera choice persists as a player preference")
	view.settings_path="";DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.session_menu.set_open(false)
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.app_focused=true
	await wait_for(game.world_vehicle.scene_ready,15)
	var result:String=game.world_vehicle.spawn(game,-1,true)
	check(game.world_vehicle.last_spawn_identity>0,"vehicle fixture admits on real nearby forest ground: "+result)
	if game.world_vehicle.last_spawn_identity>0:
		var id:int=game.world_vehicle.last_spawn_identity;var car:RigidBody3D=game.world_vehicle.activation.residents[id]
		game.player.global_position=car.global_position+Vector3.RIGHT*2.8
		var entered:bool=game.world_vehicle.enter(game,id)
		view.update()
		check(entered and view.enabled and not view.active and game.camera.current,"vehicle entry gives the vehicle camera control while remembering third person")
		if entered:
			view.set_enabled(false);view.set_enabled(true)
			check(game.camera.current and not view.active,"changing the preference while driving leaves the vehicle camera in control")
			car.set_physics_process(false);car.linear_velocity=Vector3.ZERO
			var exited:String=game.world_vehicle.exit_vehicle(game);view.update()
			check(exited.begins_with("On foot") and view.active and view.third_camera.current,"vehicle exit restores the selected on-foot third-person view")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("THIRD_PERSON_VIEW checks=",checks," failures=",failures);quit(1 if failures else 0)
