# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var game:Node
var folder:="res://reports/combat_world"
var saving:=false
var restoring:=false
var simulated_input:=true
var crater:=Vector3.ZERO
var blasted_cell:=Vector3i.ZERO
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func ticks(count:int)->void:
	for i in count:
		await physics_frame
		game.app_focused=true
func amount(item:int)->int:
	var count:=0
	for slot:Dictionary in game.player_hud.inventory.snapshot().slots:
		if slot.item==item:count+=int(slot.count)
	return count
func density(point:Vector3)->float:
	var token:int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
	var replies:Array=[]
	var callback:Callable=func(reply:Dictionary):
		if reply.token==token:replies.append(reply)
	game.terrain.density_batch_ready.connect(callback)
	var deadline:=Time.get_ticks_msec()+10000;var requested:=false
	while replies.is_empty() and Time.get_ticks_msec()<deadline:
		if not requested:requested=game.terrain.request_interpolated_density_batch(PackedVector3Array([point]),token)
		await process_frame
	game.terrain.density_batch_ready.disconnect(callback)
	return replies[0].values[0] if not replies.is_empty() and replies[0].status=="ok" else NAN
func save_checkpoint(base:Vector3,word:int)->void:
	game.combat.set_physics_process(false)
	game.combat.set_integrity(true)
	var first:=Vector3i((base+Vector3(-3,4,2)).floor());var second:=first+Vector3i(1,0,0)
	game.structures.blocks.set_cells(PackedInt32Array([first.x,first.y,first.z,word,second.x,second.y,second.z,word]))
	game.world_attack.durability.hit(game.world_attack.block_key(first),60,10)
	var job:={"center":Vector3(second)+Vector3.ONE*.5,"records":PackedInt32Array([first.x,first.y,first.z,word,second.x,second.y,second.z,word]),"offset":4}
	game.combat.blast_jobs.assign([job])
	var barrel:int=game.combat.barrels.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,base+Vector3(0,0,-5)),game.combat.barrels),AABB())
	game.combat.damage_barrel(barrel,17)
	var sample:float=await density(crater)
	check(is_finite(sample) and sample>=0,"checkpoint crater is air in the volumetric density field")
	var expected:={"rounds":game.combat.state.get_rounds(),"ammo":amount(221),"assault_rounds":game.combat.state.get_rounds(8),"assault_ammo":amount(223),"job":job,"first":first,"second":second,"barrel":barrel,"crater":crater,"density":sample,"blasted_cell":blasted_cell}
	var file:=FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE);file.store_var(expected);file.close()
	game.terrain.changed_since_save=true
func restore_checkpoint()->void:
	var file:=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ);var expected:Dictionary=file.get_var(false);file.close()
	check(game.combat.state.get_rounds()==expected.rounds and amount(221)==expected.ammo,"fresh process restores exact magazine and reserve ammunition")
	check(game.combat.state.get_rounds(8)==expected.assault_rounds and amount(223)==expected.assault_ammo,"fresh process independently restores Ranger magazine and cartridges")
	check(game.combat.state.integrity_enabled(),"fresh process restores optional integrity on")
	check(game.combat.blast_jobs==[expected.job],"fresh process restores partially completed blast and cursor")
	check(not game.combat.barrels.get_instance(expected.barrel).is_empty() and game.world_attack.durability.damage("model:%s:%d"%[game.combat.Barrel.KEY,expected.barrel],50)==17,"fresh process restores surviving barrel and partial damage")
	check(game.structures.blocks.get_cell(expected.blasted_cell)==0,"blast-destroyed building cell remains absent after reopening")
	var sample:float=await density(expected.crater)
	check(is_finite(sample) and is_equal_approx(sample,expected.density),"fresh process restores identical crater density")
	game.combat.set_integrity(false);game.combat.set_physics_process(true)
	await ticks(12)
	check(game.structures.blocks.get_cell(expected.first)!=0 and game.world_attack.durability.damage(game.world_attack.block_key(expected.first),60)==10,"resumed blast never redamages its completed prefix")
	check(game.structures.blocks.get_cell(expected.second)==0 and game.combat.blast_jobs.is_empty(),"resumed blast finishes its remaining cell exactly once")
func finish()->void:
	check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0 and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"offscreen journey never captures the desktop pointer")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"compound world shuts down after published edits")
	game.free();await process_frame;await process_frame
	print("COMBAT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
func mouse(button:int,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
func picture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func ranger_checks(base:Vector3)->void:
	var combat:Node=game.combat;var human:Node=game.tool_view.human
	var carbine:int=combat.state.get_rounds();var old_reserve:=amount(221)
	check(game.player_hud.equip_item(8),"inventory equips newly authored Ranger assault rifle")
	await ticks(85)
	check(human.current==8 and combat.state.get_rounds(8)==0,"Ranger starts with its own empty magazine")
	check(combat.reload(),"Ranger accepts matching ammunition")
	await ticks(75);await picture("ranger_reload")
	await ticks(110)
	check(combat.state.get_rounds(8)==30 and amount(223)==60 and combat.state.get_rounds()==carbine and amount(221)==old_reserve,"Ranger reload consumes only its cartridges and leaves carbine untouched")
	game.camera.look_at(game.camera.global_position+Vector3(0,0,-8));await ticks(15);await picture("ranger_idle")
	mouse(MOUSE_BUTTON_RIGHT,true);await ticks(25);await picture("ranger_aim")
	check(human.rifle_aiming and human.active_clip=="FP_Rifle_Aim" and human.model.position.distance_to(Vector3(0,-.030,-.23))<.001,"Ranger aiming aligns its sight plane with the first-person camera")
	var target:=Vector3i((base+Vector3(-2,3,-3)).floor());var word:int=game.structures.blocks.encode_block(1,0,1)
	game.structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,word]));game.structures.blocks.flush_bakes();await ticks(3)
	game.camera.look_at(Vector3(target)+Vector3.ONE*.5)
	check(combat.fire(),"Ranger trigger launches an aimed projectile")
	await picture("ranger_fire");await ticks(10)
	check(game.world_attack.durability.damage(game.world_attack.block_key(target),60)==12 and combat.state.get_rounds(8)==29,"Ranger projectile applies its own block damage and consumes one round")
	var before:int=combat.shots
	mouse(MOUSE_BUTTON_LEFT,true);await ticks(33);mouse(MOUSE_BUTTON_LEFT,false)
	var burst:int=combat.shots-before
	check(burst>=5 and burst<=6,"holding one trigger press fires a bounded 600 RPM burst")
	check(combat.state.get_rounds(8)==29-burst and combat.state.get_rounds()==carbine,"each automatic projectile consumes exactly one Ranger round")
	await ticks(12);check(combat.shots==before+burst,"releasing trigger stops automatic fire")
	mouse(MOUSE_BUTTON_RIGHT,false)
	game.session_menu.set_open(true);check(not combat.fire() and not combat.reload(),"menus block new automatic rifle actions")
	game.session_menu.set_open(false);game.app_focused=true;await ticks(3)
	var reserve:=amount(223);var magazine:int=combat.state.get_rounds(8)
	check(combat.reload(),"partial Ranger magazine can reload")
	await ticks(20);game.player_hud.equip_item(7);await ticks(90)
	check(combat.reload_slot<0 and amount(223)==reserve and combat.state.get_rounds(8)==magazine and combat.state.get_rounds()==carbine,"switching weapons cancels reload without transferring any ammunition")
	game.player_hud.equip_item(8);await ticks(85)
	# Fire away from the player and continue beyond empty; no deferred shots or underflow.
	game.camera.look_at(game.camera.global_position+Vector3(0,.8,-8));before=combat.shots
	mouse(MOUSE_BUTTON_LEFT,true);await ticks(190);mouse(MOUSE_BUTTON_LEFT,false)
	check(combat.state.get_rounds(8)==0 and combat.shots-before==magazine and not combat.fire(),"held trigger exhausts exactly the remaining magazine and empty fire is rejected")
	await ticks(30);check(combat.reload(),"empty automatic rifle can reload")
	await ticks(185)
	check(combat.state.get_rounds(8)==30 and amount(223)==reserve-30,"empty reload restores full thirty-round magazine")
	check(combat.fire(),"post-reload automatic rifle fires again");await ticks(12)
	check(combat.state.get_rounds(8)==29 and combat.state.get_rounds()==carbine,"independent non-full magazines are ready for persistence check")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--combat-output="):folder=arg.trim_prefix("--combat-output=")
		saving=saving or arg=="--combat-save-check"
		restoring=restoring or arg=="--combat-restore"
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=not saving;root.add_child(game)
	game.combat.action_input_owned=func()->bool:return simulated_input
	if restoring:game.combat.set_physics_process(false)
	var deadline:=Time.get_ticks_msec()+90000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"integrated world becomes ready")
	if game.loading_active:game.free();quit(1);return
	game.player_view.entry.finish();game._clear_motion();game.app_focused=true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);simulated_input=true
	if restoring:await restore_checkpoint();await finish();return
	game.zombies.population_enabled=false;game.zombies.clear();await ticks(3)
	var inventory:RefCounted=game.player_hud.inventory
	inventory.grant_items(PackedInt64Array([7,1,221,90,222,3,8,1,223,90]),inventory.snapshot().revision)
	check(game.player_hud.equip_item(7),"existing inventory equips carried carbine")
	await ticks(45)
	simulated_input=true
	print("COMBAT_USE ",{"can_use":game.combat.can_use(),"active":game.combat.active(),"mouse":Input.mouse_mode,"developer":game.session_menu.developer,"equipped":game.equipped_tool,"human":game.tool_view.human.current,"clip":game.tool_view.human.active_clip,"remaining":game.tool_view.human.action_remaining,"ammo":game.combat.rounds_in_bag(),"edit":game._model_edit_available()})
	check(game.combat.reload(),"real reload accepts ammunition")
	await ticks(75)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("reload.png"))
	await ticks(110)
	check(game.combat.state.get_rounds()==30 and game.combat.rounds_in_bag()==60,"authored reload transfers exactly thirty cartridges")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("rifle.png"))
		var aim_event:=InputEventMouseButton.new();aim_event.button_index=MOUSE_BUTTON_RIGHT;aim_event.pressed=true;Input.parse_input_event(aim_event);Input.flush_buffered_events()
		await ticks(40);await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("aim.png"))
		aim_event.pressed=false;Input.parse_input_event(aim_event);Input.flush_buffered_events()
	var base:Vector3=game.player.global_position
	var cell:=Vector3i((base+Vector3(0,2,-4)).floor());var word:int=game.structures.blocks.encode_block(1,0,1)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,word])),"block target placed")
	game.structures.blocks.flush_bakes();await ticks(3)
	game.camera.look_at(Vector3(cell)+Vector3.ONE*.5)
	check(game.combat.fire(),"live trigger fires a projectile")
	await ticks(32)
	check(game.combat.hits>0 and game.combat.state.get_rounds()==29,"swept projectile hits and consumes one round")
	check(game.world_attack.durability.damage(game.world_attack.block_key(cell),60)==18,"bullet damage reaches per-block durability")
	game.session_menu.set_open(true)
	check(not game.combat.fire() and not game.combat.reload(),"menus block combat actions")
	game.session_menu.set_open(false);game.app_focused=true;simulated_input=true
	await ticks(2)
	check(game.zombies.enabled,"launcher enables ordinary zombie encounters")
	var zombie:CharacterBody3D
	for offset in [Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2),Vector3(3,0,3)]:
		zombie=game.zombies.spawn_at(base+offset)
		if zombie!=null:break
	check(zombie!=null,"projectile fixture admits a real zombie on streamed terrain")
	if zombie!=null:
		zombie.set_behavior(false);await ticks(5)
		var before:float=zombie.health
		var target:Vector3=zombie.global_position+Vector3.UP*1.2
		var shot:Dictionary=game.zombies.pick(game.camera.global_position,target,[game.player.get_rid()])
		if shot.is_empty():
			target=zombie.global_position+Vector3.UP*1.5
			shot=game.zombies.pick(game.camera.global_position,target,[game.player.get_rid()])
		check(not shot.is_empty(),"firearm ray resolves the live anatomical surface")
		if not shot.is_empty():
			game.combat.launch(game.camera.global_position,(target-game.camera.global_position).normalized(),8);await ticks(15)
			check(zombie.health<before,"travelling Ranger projectile invokes the zombie firearm response even with carbine equipped")
	game.zombies.clear();await ticks(2)
	check(game.player_hud.equip_item(222),"barrel item is equippable")
	var placement_ray:Dictionary=game.structures.blocks.raycast_scene(base+Vector3(0,3,2),base+Vector3(0,-3,2),1,[])
	if not placement_ray.is_empty():
		game.camera.look_at(placement_ray.position);simulated_input=true
		var supply:=amount(222)
		check(game.combat.place_barrel(),"right-click placement uses native inventory and model transaction")
		check(amount(222)==supply-1,"placed barrel consumes one carried item")
		check(not game.combat.place_barrel() and amount(222)==supply-1,"overlapping barrel placement cannot consume another item")
		for placed:int in game.combat.barrels.get_ids():game.combat.barrels.remove_instances(PackedInt64Array([placed]))
	game.player_hud.equip_item(7);await ticks(45)
	var barrel_point:Vector3=base+Vector3(4,0,0)
	var ray:Dictionary=game.structures.blocks.raycast_scene(barrel_point+Vector3.UP*4,barrel_point-Vector3.UP*4,1,[])
	check(not ray.is_empty(),"blast fixture finds actual volumetric ground")
	if not ray.is_empty():
		barrel_point=ray.position+Vector3.UP*.02
		crater=barrel_point+Vector3.UP*.2
		var barrel:int=game.combat.barrels.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,barrel_point),game.combat.barrels),AABB())
		check(barrel>0,"barrel is a persistent native model placement")
		var chained:int=game.combat.barrels.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,barrel_point+Vector3(3,0,0)),game.combat.barrels),AABB())
		var wall:=Vector3i((barrel_point+Vector3(1,1,0)).floor())
		blasted_cell=wall
		game.structures.blocks.set_cells(PackedInt32Array([wall.x,wall.y,wall.z,word]));game.structures.blocks.flush_bakes();await ticks(5)
		game.camera.look_at(barrel_point+Vector3.UP*.5)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("barrel.png"))
		var revision:int=game.terrain.density_revision
		var stone:=amount(201)
		check(game.combat.fire(),"live trigger fires at the explosive barrel")
		await ticks(32)
		check(game.world_attack.durability.damage("model:%s:%d"%[game.combat.Barrel.KEY,barrel],50)==35,"swept projectile damages the placed native barrel")
		check(game.combat.fire(),"second live shot ignites the damaged barrel")
		deadline=Time.get_ticks_msec()+45000
		while (game.combat.explosions<2 or game.terrain.pending_edit) and Time.get_ticks_msec()<deadline:await ticks(1)
		await ticks(20)
		check(game.combat.explosions==2 and game.combat.barrels.get_instance(barrel).is_empty() and game.combat.barrels.get_instance(chained).is_empty(),"chain reaction detonates each persistent barrel exactly once")
		check(game.terrain.density_revision>revision,"blast carves terrain through the mining publication pipeline")
		check(amount(201)==stone and game.player_hud.reward_inbox.get_pending().is_empty(),"environmental crater does not grant player mining rewards")
		check(game.structures.blocks.get_cell(wall)==0 and game.combat.destroyed_blocks>0,"blast demolishes an individual building block")
		check(not game.combat.effects.fragments.is_empty(),"destroyed blocks become simulated rigid bodies")
		if DisplayServer.get_name()!="headless":
			game.camera.look_at(barrel_point);await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("blast.png"))
			await ticks(40);await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("crater.png"))
		game.session_menu.set_open(true);await ticks(3)
		check(not game.combat.effects.fragments.is_empty() and game.combat.effects.fragments[0].body.freeze,"pause freezes debris without removing collision")
		game.session_menu.set_open(false);game.app_focused=true;simulated_input=true
	game.combat.set_integrity(true)
	var floating:=Vector3i((base+Vector3(-4,5,0)).floor())
	game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,word]));game.structures.blocks.flush_bakes()
	deadline=Time.get_ticks_msec()+30000
	while game.structures.blocks.get_cell(floating)!=0 and Time.get_ticks_msec()<deadline:await ticks(1)
	check(game.structures.blocks.get_cell(floating)==0,"optional integrity drops a floating block in the real world")
	game.combat.set_integrity(false)
	game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,word]));await ticks(120)
	check(game.structures.blocks.get_cell(floating)==word,"turning integrity off preserves unsupported blocks")
	await ranger_checks(base)
	if saving:await save_checkpoint(base,word)
	await finish()
