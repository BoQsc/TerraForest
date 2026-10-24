# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func e(pressed:bool)->InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=pressed;return event
func screenshot(name:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--items-evidence-dir="):evidence=argument.trim_prefix("--items-evidence-dir=")
	if evidence.is_empty():evidence="res://reports/gameplay_items"
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and game.session_menu.ready_to_dock,45),"playable world and session menu ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	var home:Vector3=game.player.global_position
	var hud=game.player_hud;var inventory:RefCounted=hud.inventory;var attack=game.world_attack
	check(not game.session_menu.developer,"paid gameplay is active")
	# The ordinary repair hammer never selects a construction editor/preview.
	hud.equip_item(3)
	check(game.equipped_tool==3 and not game.structure_mode and game.session_menu.developer_hud.context_slot()==-1,"repair hammer has no building mode or tool-settings panel")
	var base:=Vector3i(home.floor())+Vector3i(0,10,0)
	game.structures.blocks.set_focus(Vector3(base));game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33]))
	aim(Vector3(base)+Vector3(0,0,3),Vector3(base)+Vector3.ONE*.5)
	game.camera.global_position=Vector3(base)+Vector3(.5,.5,2.5)
	game.camera.look_at(Vector3(base)+Vector3.ONE*.5)
	for i in 4:await physics_frame
	var key:String=attack.block_key(base)
	attack.durability.hit(key,60,40)
	var wear:int=inventory.snapshot().slots[hud.active_slot].wear
	check(attack.attack(true) and attack.durability.damage(key,60)==40,"repair windup does not mutate durability")
	check(await preload("res://tests/swing_driver.gd").finish(game) and attack.durability.damage(key,60)==15 and inventory.snapshot().slots[hud.active_slot].wear==wear+1,"repair applies exactly once at hammer contact and costs wear")
	attack.next_attack=0;attack.attack(true);await preload("res://tests/swing_driver.gd").finish(game)
	wear=inventory.snapshot().slots[hud.active_slot].wear
	attack.next_attack=0;attack.attack(true);await preload("res://tests/swing_driver.gd").finish(game)
	check(attack.durability.damage(key,60)==0 and inventory.snapshot().slots[hud.active_slot].wear==wear,"fully repaired targets consume no hammer wear")
	for item:int in [1,2,3,4,5]:
		hud.equip_item(item);game.target_overlay.enabled=true;game.target_overlay.timer=0;game.target_overlay._process(.2)
		check(game.target_overlay.visible,"global targeting overlay works for item %d"%item)
	hud.equip_item(3);game.target_overlay.enabled=false;game.target_overlay._process(.2)
	check(not game.target_overlay.visible,"targeting overlay can be disabled for repair hammer")
	await screenshot("repair_hammer")
	game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,0]))
	# Exercise ordinary equipment + right-click, not only the terrain facade.
	aim(home,home+Vector3(0,0,-2));inventory.grant(211,3,inventory.snapshot().revision);hud.refresh();hud.equip_item(211)
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
	game._unhandled_input(right)
	check(game.terrain.pending_edit and amount(211)==2,"held mined soil right-click submits a paid terrain edit")
	check(await wait_for(func():return not game.terrain.pending_edit,15) and amount(211)==2,"soil publishes through normal streamed terrain")
	await screenshot("placed_soil")
	# Developer entries spawn actual collectible stacks rather than silent grants.
	game.session_menu.set_open(true);game.session_menu.show_page("Developer")
	var before:int=amount(211);game.session_menu.spawner.spawn(211)
	check(amount(211)==before and game.session_menu.opened,"gameplay cannot use the developer spawner")
	game.session_menu.toggle_developer();game.session_menu.show_page("Developer")
	await screenshot("developer_spawner")
	game.session_menu.spawner.count.value=7;game.session_menu.spawner.entries[211].pressed.emit()
	print("SPAWNER_RESULT ",game._lake_notice)
	check(not game.session_menu.opened and amount(211)==before,"developer click creates a world pickup without granting inventory")
	var collected:Dictionary=game.pickups.collect_near(home+Vector3.UP*.5,inventory,game._pickup_reachable)
	check(collected.ok and amount(211)==before+7,"spawned native pickup collects the chosen stack count: "+str(collected))
	game.session_menu.toggle_developer()
	# A real fleet body participates in hold-E, carried damage and redeployment.
	aim(home,home+Vector3(0,0,-6))
	var session=game.world_vehicle
	if not check(session.fleet_enabled and await wait_for(session.scene_ready,15),"vehicle fleet resource ready"):await finish();return
	var ray:=PhysicsRayQueryParameters3D.create(home+Vector3(0,8,-6),home+Vector3(0,-8,-6),3,[game.player.get_rid()])
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not check(not hit.is_empty(),"vehicle fixture has real ground"):await finish();return
	var pose:=Transform3D(Basis.IDENTITY,hit.position+Vector3.UP*.85)
	var id:int=session.fleet.spawn(pose)
	game.terrain.focus=pose.origin
	if not check(await wait_for(func():return session.activation.residents.has(id),20),"fleet activates its actual vehicle body"):await finish();return
	var body:RigidBody3D=session.activation.residents[id]
	aim(body.position+Vector3(2.8,-.85,0),body.position+Vector3.UP*.3)
	for i in 4:await physics_frame
	check(session.candidate(game)==id,"vehicle action candidate passes range and line of sight")
	var radial=game.vehicle_radial
	check(radial.consume(e(true)) and not session.driving,"E press waits for tap versus hold")
	check(radial.consume(e(false)) and session.driving,"E tap keeps default enter action")
	body.set_physics_process(false);body._drive_speed=25;body.linear_velocity=Vector3(0,0,25)
	game._unhandled_input(e(true))
	var message:String=game._lake_notice
	check(message.begins_with("On foot") and not session.driving and not body.freeze and body.linear_velocity.length()>20 and game.player.velocity.length()>20,"E exits at driving speed immediately and preserves vehicle/player momentum")
	body.freeze=true;body.set_physics_process(false);body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO;session.coasting.clear()
	aim(body.position+Vector3(2.8,-.85,0),body.position+Vector3.UP*.3)
	check(radial.consume(e(true)),"hold-E begins vehicle actions")
	radial.held_since=Time.get_ticks_msec()-400;radial._process(0)
	check(radial.opened and not session.driving,"holding E opens radial without entering")
	await screenshot("vehicle_radial")
	radial.cancel();check(not radial.opened and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"cancel restores aim without entering or picking up")
	attack.durability.hit("vehicle:%d"%id,300,73)
	radial.consume(e(true));radial.held_since=Time.get_ticks_msec()-400;radial._process(0)
	game.player.position+=Vector3.RIGHT*10;radial.activate(1)
	check(session.fleet.get_record(id).present and amount(501)==0,"moving out of range while radial is open cancels pickup without creating an item")
	aim(body.position+Vector3(2.8,-.85,0),body.position+Vector3.UP*.3)
	var carried:PackedByteArray=inventory.capture_storage_snapshot()
	var full:Dictionary=inventory.snapshot()
	for row:Dictionary in full.slots:
		if row.item==0:row.item=101;row.count=999
	inventory.restore(full,full.revision)
	check(session.pickup(game,id).begins_with("Make an empty") and session.fleet.get_record(id).present,"full inventory leaves the vehicle in the world")
	inventory.restore_storage_snapshot(carried);hud.refresh()
	radial.consume(e(true));radial.held_since=Time.get_ticks_msec()-400;radial._process(0);radial.activate(1)
	message=game._lake_notice
	check(message.begins_with("Vehicle picked up") and not session.fleet.get_record(id).present and amount(501)==1,"pickup replaces exactly one parked vehicle with one carried item")
	var vehicle_slot:int=slot_of(501)
	check(vehicle_slot>=0 and inventory.snapshot().slots[vehicle_slot].wear==73,"carried vehicle preserves structural damage")
	var chest:RefCounted=ClassDB.instantiate("NativeContainerStore");chest.configure(inventory,1)
	check(chest.deposit(1,inventory,vehicle_slot,1,inventory.snapshot().revision,chest.snapshot(1).store_revision).ok and chest.snapshot(1).slots[0].wear==73,"vehicle deposits into ordinary storage with its damage")
	var chest_bytes:PackedByteArray=chest.capture_storage_snapshot();chest.restore_storage_snapshot(chest_bytes)
	check(chest.withdraw(1,inventory,0,1,inventory.snapshot().revision,chest.snapshot(1).store_revision).ok and inventory.snapshot().slots[slot_of(501)].wear==73,"saved vehicle storage withdraws without repairing or duplicating")
	vehicle_slot=slot_of(501);hud.refresh();hud.set_open(true);await screenshot("vehicle_inventory");hud.set_open(false)
	var drop:Dictionary=game.pickups.drop_stack(inventory,vehicle_slot,inventory.snapshot().revision,home+Vector3.UP*.3,1)
	check(drop.ok and amount(501)==0,"vehicle inventory item drops through ordinary native stack transfer")
	check(game.pickups.collect_near(home+Vector3.UP*.3,inventory,func(_p):return true).ok and inventory.snapshot().slots[slot_of(501)].wear==73,"recollecting vehicle cannot repair it")
	aim(home,pose.origin-Vector3.UP*.85);hud.equip_item(501)
	game._unhandled_input(right)
	check(session.last_spawn_identity>0 and amount(501)==0 and attack.durability.damage("vehicle:%d"%session.last_spawn_identity,300)==73,"right-click redeploys carried vehicle with the same damage and no duplicate item")
	await screenshot("vehicle_item_deployed")
	await finish()
func finish()->void:
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"compound world closes consistently")
	game.free();await process_frame
	print("GAMEPLAY_ITEMS failures=",failures);quit(1 if failures else 0)
