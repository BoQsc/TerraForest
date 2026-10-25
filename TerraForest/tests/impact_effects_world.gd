# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var evidence:String
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func wait_for(predicate:Callable,seconds:int=20)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func aim(feet:Vector3,point:Vector3)->void:
	game.player.position=feet;game.camera.position=Vector3(0,1.62,0);game.camera.look_at(point)
	game.app_focused=true;game.fly=false;game.needs_floor_spawn=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func finish_swing()->bool:
	return await wait_for(func():return game.world_attack.pending.is_empty(),4) and game.world_attack.last_hit
func verify(ok:bool,label:String)->bool:
	checks+=1;return check(ok,label)
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
func strike()->bool:
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.world_attack.next_attack=0
	return game.world_attack.attack() and await finish_swing()
func run()->void:
	evidence="res://reports/impact_effects/world"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-evidence="):evidence=arg.trim_prefix("--effects-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	ProjectSettings.set_setting("terraforest/impact_effects_settings_path","")
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.player_view.settings_path="";root.add_child(game)
	if not verify(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"temporary world reaches playable state"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.ground_enabled=false
	game.zombies.clear();game.zombies.population_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false)
	var effects=game.impact_effects;var attack=game.world_attack;var hud=game.player_hud
	var no_module:bool="--no-impact-effects" in OS.get_cmdline_user_args()
	verify((effects==null)==no_module,"optional module startup matches launch setting")
	var ground:Vector3=game.player.position
	var base:=Vector3i(ground.floor())+Vector3i(0,10,0)
	game.structures.blocks.set_focus(Vector3(base));game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,97]))
	aim(Vector3(base)+Vector3(0,0,3),Vector3(base)+Vector3.ONE*.5)
	game.camera.global_position=Vector3(base)+Vector3(.5,.5,2.5);game.camera.look_at(Vector3(base)+Vector3.ONE*.5)
	hud.equip_item(1)
	if not verify(await wait_for(func():return attack.target().get("kind")=="block",5),"metal block has real published collision"):await finish();return
	if no_module:
		verify(game.session_menu.impact_toggle==null and await strike() and attack.durability.damage(attack.block_key(base),180)==30,"module omitted: menu and ordinary attack still work")
		await finish();return
	var original:bool="--effects-baseline" in OS.get_cmdline_user_args()
	verify(effects.style==0,"old settings without a style default to grounded")
	if original:effects.set_style(1,false)
	verify(effects.pool.is_empty(),"no emitters allocated before first impact")
	verify(attack.target().material_id==3 and attack.target().has("position") and attack.target().has("normal"),"metal material and surface pose survive actual target query")
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	verify(attack.attack() and effects.emitted_events==0,"windup produces no particles")
	verify(await wait_for(func():return effects.emitted_events==1,3) and effects.last_event.material=="metal","authored contact emits one metal spark burst")
	await create_timer(.08).timeout;await capture("metal_contact")
	verify(await finish_swing() and effects.emitted_events==1 and attack.durability.damage(attack.block_key(base),180)==30,"one contact: one damage event and one cosmetic burst")
	game.session_menu.impact_toggle.button_pressed=false
	verify(not effects.enabled and effects.pool.is_empty() and game.session_menu.breakup_toggle.disabled,"ESC master toggle clears active particles immediately")
	var wear:int=hud.inventory.snapshot().slots[hud.active_slot].wear
	verify(await strike() and effects.emitted_events==1 and attack.durability.damage(attack.block_key(base),180)==60 and hud.inventory.snapshot().slots[hud.active_slot].wear==wear+1,"disabled effects preserve damage and tool wear")
	game.session_menu.impact_toggle.button_pressed=true
	var count:int=effects.emitted_events
	attack.next_attack=0;verify(attack.attack(),"cancellation check starts real swing");attack.cancel()
	await create_timer(.7).timeout
	verify(effects.emitted_events==count,"cancelled swing has no particles")
	# One normal hit remains before destruction, then real final contact gets the larger burst.
	attack.durability.hit(attack.block_key(base),180,90)
	verify(await strike() and effects.last_event.broken and effects.last_event.count==41 and game.structures.blocks.get_cell(base)==0,"accepted metal destruction gets the optional larger burst")
	game.session_menu.breakup_toggle.button_pressed=false
	game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33]))
	await physics_frame;await physics_frame
	attack.durability.hit(attack.block_key(base),60,50)
	verify(await strike() and effects.last_event.material=="wood" and not effects.last_event.broken and effects.last_event.count==14,"breakup toggle retains small hit splinters on destruction")
	game.session_menu.breakup_toggle.button_pressed=true
	# Material query is actually serviced by the native terrain worker.
	var origin:=ground+Vector3(15,50,15)
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin-Vector3.UP*200,1))
	if verify(not hit.is_empty(),"nearby terrain available for excavation"):
		hud.equip_item(5)
		if game.equipped_tool!=5:
			hud.inventory.grant(5,1,hud.inventory.snapshot().revision);hud.refresh();hud.equip_item(5)
		game.player.position=hit.position+Vector3.UP*.2;game.camera.global_position=hit.position+Vector3.UP*2;game.camera.look_at(hit.position,Vector3.FORWARD)
		effects.prepare_contact(game.camera.global_position,hit.position-Vector3.UP)
		verify(await wait_for(func():return effects.sample.has("surface_material"),5),"native worker supplies material plus depth within bounded prefetch")
		var target:Dictionary=attack.target();var expected:String=effects.material_for(target)
		verify(target.get("kind")=="terrain" and expected in ["soil","stone","sand","snow","asphalt","iron","copper"],"terrain visual material classified independently of damage")
		count=effects.emitted_events;var revision:int=game.terrain.density_revision
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;attack.next_attack=0
		verify(attack.attack() and await wait_for(func():return effects.emitted_events==count+1,4),"shovel contact emits debris")
		await create_timer(.1).timeout;await capture("terrain_contact")
		verify(await wait_for(func():return attack.pending.is_empty() and not game.terrain.pending_edit,20) and game.terrain.density_revision>revision and not game.mining_rewards.failed,"cosmetic debris preserves native excavation and mining rewards")
		verify(effects.last_event.material==expected and effects.last_event.broken,"dig uses the sampled surface material and excavation burst")
	# Bound saturation and reuse independently of attack rate.
	effects.set_enabled(false,false);effects.set_enabled(true,false)
	for i in effects.POOL_LIMIT:verify(effects.burst(game.camera.global_position+Vector3.DOWN,Vector3.UP,"stone"),"bounded pool accepts burst "+str(i))
	verify(not effects.burst(game.camera.global_position,Vector3.UP,"metal") and effects.statistics().particle_capacity==384,"saturated pool drops cosmetic overflow at 384 GPU slots")
	verify(await wait_for(func():return effects.statistics().active==0,4),"one-shot GPU emitters finish and retire")
	verify(effects.burst(game.camera.global_position+Vector3.DOWN,Vector3.UP,"soil") and effects.pool.size()==8,"retired emitter reused without allocation")
	verify(effects.pool[0].draw_passes==(1 if original else 2),"selected style supplies baseline meshes or textured chips plus dust")
	# Exercise the actual ESC signal; switching must retire active resources.
	game.session_menu.impact_style.item_selected.emit(1)
	verify(effects.style==1 and game.session_menu.impact_style.selected==1,"ESC selects original baseline immediately")
	game.session_menu.impact_style.item_selected.emit(0)
	verify(effects.style==0 and effects.pool.is_empty() and game.session_menu.impact_style.selected==0,"switch to grounded clears old live emitters")
	effects.burst(game.camera.global_position+Vector3.DOWN,Vector3.UP,"soil")
	game.session_menu.impact_style.item_selected.emit(1)
	verify(effects.style==1 and effects.pool.is_empty(),"switch back to baseline also clears live resources")
	# Isolate saved preferences from the player's real settings.
	var path:="user://impact_test_"+str(Time.get_ticks_usec())+".cfg"
	effects.settings_path=path;effects.set_enabled(false);effects.set_breakup_enabled(false)
	var config:=ConfigFile.new();verify(config.load(path)==OK and config.get_value("effects","enabled")==false and config.get_value("effects","breakup")==false,"both settings persist independently")
	var again=load("res://addons/impact_effects/impact_effects.gd").new();again.settings_path=path;game.add_child(again);again.attach(game)
	verify(not again.enabled and not again.breakup_enabled and again.style==1,"new module restores saved toggles and baseline style")
	again.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(path));effects.settings_path=""
	effects.set_enabled(true,false);effects.set_breakup_enabled(true,false)
	effects.set_style(1 if original else 0,false)
	game.session_menu.set_open(true);await process_frame;await capture("esc_settings")
	await finish()
func finish()->void:
	game.shutdown_requested=true
	verify(await game.terrain.shutdown_after_edits(),"temporary world shuts down consistently")
	game.free();await process_frame;await process_frame
	print("IMPACT_EFFECTS_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
