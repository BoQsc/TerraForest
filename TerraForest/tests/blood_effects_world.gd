extends SceneTree
var game:Node
var failures:=0
var checks:=0
var folder:="res://reports/blood_effects/world"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func finish_swing()->bool:
	return await wait_for(func():return game.world_attack.pending.is_empty(),4) and game.world_attack.last_hit
func ready_swing()->void:
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.world_attack.next_attack=0
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--effects-evidence="):folder=argument.trim_prefix("--effects-evidence=")
	DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/impact_effects_settings_path","")
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"temporary world reaches play"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.ground_enabled=false
	game.zombies.clear();game.zombies._spawn_clock=100000
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.player_hud.equip_item(2);ready_swing()
	var zombie:Node3D
	for offset in [Vector3(0,0,2),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,-2)]:
		zombie=game.zombies.spawn_at(game.player.global_position+offset)
		if zombie!=null:break
	if not check(zombie!=null,"live zombie spawns on real forest terrain"):await finish();return
	zombie.set_behavior(false);zombie.set_physics_process(false);zombie.animation_player.pause();zombie.skeleton.force_update_all_bone_transforms()
	var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes.torso,Transform3D.IDENTITY)
	var point:Vector3=mesh.get_aabb().get_center()
	game.player.position=Vector3(point.x,zombie.global_position.y,point.z+2)
	game.camera.global_position=point+Vector3.BACK*2;game.camera.look_at(point)
	var attack=game.world_attack;var effects=game.impact_effects
	var target:Dictionary=attack.target()
	if not check(target.get("kind")=="zombie" and target.get("part")=="torso" and target.has("normal"),"held-tool ray resolves a visible flesh surface and normal"):await finish();return
	var health:float=zombie.health;var limb:float=zombie.limb_health.torso
	var wear:int=game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].wear
	check(attack.attack() and effects.emitted_events==0,"real animation windup emits no blood")
	check(await wait_for(func():return effects.emitted_events==1,4),"authored contact emits exactly one blood burst")
	check(effects.last_event.get("material")=="flesh" and effects.last_event.position.distance_to(target.position)<.1,"blood originates at the hit surface, not actor origin")
	await create_timer(.08).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("zombie_contact.png"))
	check(await finish_swing() and effects.emitted_events==1 and zombie.health==health-15 and zombie.limb_health.torso==limb-15 and game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].wear==wear+1,"cosmetic blood preserves single-contact overall/limb damage and tool wear")
	ready_swing();check(attack.attack(),"cancellable attack starts");attack.cancel();await create_timer(.8).timeout
	check(effects.emitted_events==1,"cancelled animation cannot bleed")
	game.camera.look_at(game.camera.global_position+Vector3.UP,Vector3.FORWARD);ready_swing()
	check(attack.attack() and not await finish_swing() and effects.emitted_events==1,"missed swing cannot bleed")
	game.camera.look_at(point);game.session_menu.impact_toggle.button_pressed=false;ready_swing()
	check(attack.attack() and await finish_swing() and zombie.health==health-30 and effects.emitted_events==1 and effects.pool.is_empty(),"ESC master toggle suppresses blood without suppressing damage")
	game.session_menu.impact_toggle.button_pressed=true
	var origin:Vector3=game.player.position+Vector3.UP*8
	var collection:Node3D=ClassDB.instantiate("NativeStaticBatch");game.structures.add_child(collection)
	collection.configure_asset("tests/flesh_object",BoxMesh.new());collection.set_meta("impact_material","flesh")
	collection.configure_collision(AABB(-Vector3.ONE*.5,Vector3.ONE),16,8,4);collection.set_collision_focus(origin)
	var identity:int=collection.insert_instance(PackedFloat32Array([1,0,0,origin.x,0,1,0,origin.y,0,0,1,origin.z]))
	game.structures._models["tests/flesh_object"]=collection
	game.player.position=origin+Vector3.BACK*2;game.camera.global_position=origin+Vector3.BACK*2;game.camera.look_at(origin)
	if check(await wait_for(func():return attack.target().get("kind")=="model",5),"tagged destructible flesh prop has a real targetable surface"):
		target=attack.target()
		check(target.get("impact_material")=="flesh" and target.material=="other","flesh metadata survives targeting without altering damage category")
		ready_swing();check(attack.attack() and await finish_swing() and effects.emitted_events==2 and effects.last_event.material=="flesh","accepted flesh prop damage produces blood")
		game.player_hud.equip_item(3);ready_swing()
		check(attack.attack(true) and await finish_swing() and effects.emitted_events==2,"repairing tagged flesh does not produce blood")
		game.player_hud.equip_item(2);collection.set_removal_protected(identity,true);ready_swing()
		check(attack.attack() and not await finish_swing() and effects.emitted_events==2,"rejected protected-object damage cannot produce blood")
		collection.set_removal_protected(identity,false);collection.remove_meta("impact_material");ready_swing()
		check(attack.attack() and await finish_swing() and effects.emitted_events==3 and effects.last_event.material=="stone","untagged prop returns to normal nonblood impact")
	game.structures._models.erase("tests/flesh_object");collection.free()
	zombie.receive_hit("torso",1000,point,Vector3.ZERO)
	await create_timer(2.0).timeout
	mesh=zombie._bake_cpu(zombie.part_meshes.torso,Transform3D.IDENTITY);point=mesh.get_aabb().get_center()
	game.player.position=point+Vector3.BACK*1.5;game.camera.global_position=point+Vector3(0,1.2,1.5);game.camera.look_at(point)
	target=attack.target();var emitted:int=effects.emitted_events
	if check(not zombie.alive and target.get("kind")=="zombie","corpse retains a targetable flesh surface"):
		ready_swing()
		check(attack.attack() and await wait_for(func():return effects.emitted_events==emitted+1,4) and effects.last_event.material=="flesh","accepted corpse contact also emits blood")
		await create_timer(.08).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("corpse_contact.png"))
		check(await finish_swing() and not zombie.alive and zombie.health==0,"corpse blood cannot revive or alter overall health")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("BLOOD_EFFECTS_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
