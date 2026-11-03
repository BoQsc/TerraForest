# SPDX-License-Identifier: 0BSD
extends "res://tests/trader_ride_world.gd"
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var receipt:Dictionary={}
var combat_targets:=PackedInt64Array()

func run()->void:
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	if not check(await wait_for(browser_catalog_ready),"ordinary world browser opens"):await finish();return
	var browser:=current_scene
	if stage=="create":
		receipt={"slot":"Expedition_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()}
		FileAccess.open(folder.path_join("world.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt))
		browser.name_field.text=receipt.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.world_style.get_item_text(browser.world_style.selected)=="Frontier expedition" and browser.selected_options()==Recipe.DEFAULTS,"normal default exposes the expedition without review switches")
		await photograph("default-recipe")
		browser.generate_button.pressed.emit()
		var status_path:String=browser.preparation_status
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var status=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return status is Dictionary and status.get("state","") in ["failed","cancelled"]
			return false,560)
		if not check(game_ready(),"normal Generate & play publishes the expedition"):
			print("EXPEDITION_GENERATION ",FileAccess.get_file_as_string(status_path));await finish();return
	else:
		receipt=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
		if not check(str(receipt.get("slot","")).begins_with("Expedition_1703_"),"only the owned expedition fixture reopens"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==receipt.slot:selected=index;break
		if not check(selected>=0,"My worlds lists the expedition"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
		if not check(await wait_for(game_ready,150),"normal loading restores the expedition"):await finish();return
	var game:=current_scene;game.background_fps=60;game.app_focused=true
	if stage=="create":check(game.player_notices.shown==0,"quest announcement waits until first-spawn animation finishes")
	if not check(await wait_for(func():return not game.player_view.entry.pending and not game.player_view.entry.active,20),"entry finishes before interaction"):await finish();return
	if stage=="create":check(game.player_view.entry.wake_starts==1 and not game.player_view.entry.wake_pending,"approved wake animation runs once on initial upstairs spawn")
	else:check(game.player_view.entry.wake_starts==0,"ordinary saved-world loading does not replay waking")
	if stage=="create":check(game.player_life.state.snapshot().has_spawn and game.player_life.state.snapshot().spawn.distance_to(game.player.position)<.25,"new generation persists introductory shelter before play")
	if stage=="create":
		check(await wait_for(func():return game.player_notices.shown==1 and game.player_notices.toast.modulate.a>.99,3),"Added quest notice animates after waking")
		game._show_lake_notice("Your journey begins","quest")
		check(await wait_for(func():return game.player_notices.general.visible and game.player_notices.general_age>=.15 and game.player_notices.general.modulate.a>.99,2),"general notice fades in above the toolbar")
		await photograph("quest-notice")
	else:check(game.player_notices.shown==0,"reload does not repeat Added quest notice")
	if stage=="create" and "--notices-only" in OS.get_cmdline_user_args():
		check(game.player_notices.toast.size.y<120,"rendered quest toast remains compact")
		check(game.destination_guide.panel.position.x>root.size.x*.65 and game.destination_guide.caption.text=="Talk to trader","active objective appears at upper right")
		FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var({"quests":game.quests.store.capture_storage_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot()})
		await finish();return
	if stage=="notices_reload":
		var expected:Dictionary=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		check(game.quests.store.capture_storage_snapshot()==expected.quests and game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"reload preserves introduction and inventory without another notice")
		await photograph("notice-reload");await finish();return
	if stage in ["life_save","life_reload"]:
		if stage=="life_save":
			check(await wait_for(func():return game.player_life.anchored,5),"legacy owned world gains a safe persisted shelter")
			game.zombie_target.receive_zombie_attack(13)
			check(game.player_life.state.snapshot().health==87,"ordinary target damage before save")
			FileAccess.open(folder.path_join("life.bin"),FileAccess.WRITE).store_var({"life":game.player_life.state.capture_storage_snapshot(),"inventory":game.player_hud.capture_snapshot()})
		else:
			var expected:Dictionary=FileAccess.open(folder.path_join("life.bin"),FileAccess.READ).get_var()
			check(game.player_life.state.capture_storage_snapshot()==expected.life,"fresh process restores exact native health and shelter")
			var anchor:Vector3=game.player_life.state.snapshot().spawn
			game.zombie_target.receive_zombie_attack(1000)
			check(game.player_life.dead,"restored player can die from ordinary damage")
			check(await wait_for(func():return not game.player_life.dead and not game.player_view.entry.pending and not game.player_view.entry.active,60),"death streams shelter and completes approved wake")
			check(game.player.position.distance_to(anchor)<.25 and game.player_view.entry.wake_starts==1,"exact persisted anchor returns once")
			check(game.player_hud.capture_snapshot()==expected.inventory,"durable respawn preserves inventory")
			await photograph("respawn-anchor")
		await finish();return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	physics_frame.connect(update_population)
	game.world_vehicle.interaction_available=func():return not game.player_view.entry.active and not game.loading_active and not game.shutdown_requested and game.app_focused and game.terrain.world_ready and not game.terrain.pending_edit and not game.player_hud.inventory_open
	var ride:Node=game.trader.ride
	if stage=="intro_reload":
		var expected:Dictionary=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		check(not game.player_view.entry.wake_pending and game.player_view.entry.wake_starts==0,"consumed first-spawn presentation remains consumed after reload")
		check(game.quests.store.capture_storage_snapshot()==expected.quests,"introduction quest state restores exactly")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"selected inventory and expedition supplies restore without duplication")
		check(ride.state.expedition and ride.identity()==expected.vehicle,"same expedition vehicle restores")
		await finish();return
	if stage in ["clear","clear_resume"]:await complete_mine(game,ride);return
	if stage=="mine_resume":
		if not check(ride.state.expedition and game.quests.store.snapshot().introduction==3,"saved first expedition remains active"):await finish();return
		if not check(await watch(func():return game.world_vehicle.passenger==ride,30),"saved expedition passenger restores before combat trip"):await finish();return
		if not check(await watch(func():return ride.state.phase==ride.ARRIVED,180),"saved expedition reaches the mine for combat"):await finish();return
		game.world_vehicle.exit_vehicle(game)
		if not check(game.world_vehicle.passenger==null,"player exits for first mine clear"):await finish();return
		await explore_mine(game,ride);return
	if stage=="claim_resume":
		if not check(game.quests.store.snapshot().phase==4 and ride.state.phase in [ride.HOME_WALK,ride.IDLE],"completed mine persists while trader returns home"):await finish();return
		await claim_reward(game,ride);return
	if stage=="home_resume":
		if not check(game.quests.store.snapshot().introduction==3 and ride.state.phase==ride.HOME_WALK,"unfinished expedition persists after return-home obstruction"):await finish();return
		if not check(await trader_approach(game,false),"player physically clears the saved vehicle-exit obstruction"):await finish();return
		check(await watch(func():return ride.state.phase==ride.IDLE,120),"trader recovers and returns to the counter without collision bypass")
		await photograph("home-again");await finish();return
	if stage=="reward_reload":
		var expected:Dictionary=FileAccess.open(folder.path_join("completed.bin"),FileAccess.READ).get_var()
		check(game.quests.store.snapshot().introduction==4 and game.quests.store.capture_storage_snapshot()==expected.quests,"completed quest restores exactly")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"reward and remaining expedition supplies restore exactly")
		check(ride.state.phase==ride.IDLE and ride.identity()==expected.vehicle,"same trader and vehicle remain home after completion")
		await finish();return
	if stage=="depart":
		if not check(ride.state.phase==ride.BOARDING and ride.state.expedition,"saved expedition retains its boarding state"):await finish();return
		await depart(game,ride);return
	if stage=="driver":
		await wait_for(func():return is_instance_valid(game.trader.actor),30)
		var probes:Array=[]
		for step in 17:
			var at:=Vector3(1002.5,53,518.75+step*.125)
			var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at,at-Vector3.UP*5,7,[game.player.get_rid(),game.trader.actor.get_rid()]))
			probes.append({"z":at.z,"point":hit.get("position"),"normal":hit.get("normal"),"body":str(hit.get("collider"))})
		print("ENTRANCE_PROFILE ",probes)
		check(await watch(func():return ride.state.seated,30),"saved driver continues physical boarding")
		await photograph("driver-resume");await finish();return
	if stage=="resume":
		var expected:Dictionary=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		check(ride.state.expedition and ride.identity()==expected.vehicle,"fresh process restores the same expedition vehicle")
		check(game.quests.store.capture_storage_snapshot()==expected.quests and game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process retains quest and exact supplies without another grant")
		if not check(await watch(func():return game.world_vehicle.passenger==ride,30),"saved passenger resumes the same free ride"):await finish();return
		if not check(await watch(func():return ride.state.phase==ride.ARRIVED,180),"native driver physically reaches the coal-mine road stop"):await photograph("outbound-failed");await finish();return
		check(ride.car.position.distance_to(game.quests.store.snapshot().location.marker)<80,"arrival is near the actual mine entrance")
		await photograph("mine-arrival")
		var exit_message:String=game.world_vehicle.exit_vehicle(game)
		if not check(game.world_vehicle.passenger==null and ride.state.phase==ride.ARRIVED,"normal E exit leaves the trader waiting: "+exit_message):await finish();return
		var parked:Vector3=ride.car.position
		for tick in 180:await physics_frame
		check(ride.car.position.distance_to(parked)<.15,"trader waits instead of departing without the player")
		if not check(game.world_vehicle.enter(game,ride.identity()) and ride.state.phase==ride.RETURNING,"player can return with the mine quest unfinished"):await finish();return
		if not check(await watch(func():return ride.state.phase==ride.HOME_ARRIVED,240),"native driver physically brings the passenger home"):await photograph("return-failed");await finish();return
		check(game.world_vehicle.exit_vehicle(game).contains("Home") and game.world_vehicle.passenger==null,"normal E exit releases the passenger at home")
		check(game.quests.store.snapshot().introduction==3 and game.quests.store.snapshot().phase==3,"unfinished quest remains active after returning")
		if not check(await trader_approach(game,false),"player walks clear of the vehicle exit before waiting at the counter"):await finish();return
		check(await watch(func():return ride.state.phase==ride.IDLE,120),"trader walks back to the counter")
		await photograph("home-again");await finish();return
	if not check(game.quests.store.snapshot().introduction==1,"new player starts with talk-to-trader objective"):await finish();return
	check(game.player.position.distance_to(game.trader.anchor)<200,"new player spawns in the trader neighbourhood")
	check(game.quests.marker().get("quest",false) and game.quests.marker().position==game.trader.anchor,"map and compass share the initial trader marker")
	await photograph("first-play")
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",Recipe.DEFAULTS))
	while worker.is_alive():await process_frame
	var planned:Dictionary=worker.wait_to_finish();var lot:Dictionary={}
	if not check(planned.get("ok",false),"ordinary generation plan reconstructs"):await finish();return
	for district:Dictionary in planned.sites:
		for candidate:Dictionary in district.lots:
			if candidate.asset.has_meta("trader_anchor"):lot=candidate;break
	if not check(not lot.is_empty(),"approved trader lot exists"):await finish();return
	var spawn=preload("res://addons/world_runtime/introduction_spawn.gd")
	var room:Dictionary=spawn.select(planned.sites)
	if stage=="create":
		var homes=preload("res://addons/characters/runtime/house_sleepers.gd")
		var churches:=0
		for district:Dictionary in planned.sites:
			for church:Dictionary in district.lots:
				if church.asset.get_meta("expansion_id","")!="church_c1":continue
				churches+=1
				var anchors:Array=homes.plan([church],1703).anchors;var keys:=PackedInt64Array()
				for anchor:Dictionary in anchors:keys.append(anchor.key)
				var ids:PackedInt64Array=game.zombies.population.store.authored_identities(keys)
				check(ids.size()==10 and not ids.has(0),"generated church has ten persistent authored residents")
		check(churches>0,"default recipe publishes occupied churches")
		if not check(room.ok and game.player.position.distance_to(room.position)<.25,"ordinary new world starts in the approved upstairs room"):await finish();return
		for local:Vector3 in spawn.EXIT.slice(1):
			if not check(await walk_to(game,spawn.point(room.lot,local)),"player descends existing house stairs and leaves through the door"):await photograph("upstairs-exit-failed");await finish();return
		for target:Vector3 in [room.lot.entrance.segment.finish,room.lot.entrance.segment.start]:
			if not check(await walk_to(game,target),"house entrance reaches the road without teleporting"):await finish();return
		var journey:RefCounted=ClassDB.instantiate("NativeRoadJourney")
		journey.configure(game.generated_region.store.get_plan().roads,0)
		var route:Dictionary=journey.route(game.player.position,lot.entrance.segment.start,80,Vector3.ZERO)
		if not check(route.get("ok",false),"road graph connects upstairs neighbourhood to trader"):await finish();return
		for waypoint:Vector3 in route.points:
			var begin:Vector3=game.player.position
			var count:=maxi(1,ceili(begin.distance_to(waypoint)/20))
			for index in range(1,count+1):
				if not check(await walk_to(game,begin.lerp(waypoint,float(index)/count)),"player follows the connected road to trader"):await photograph("road-walk-failed");await finish();return
	for target:Vector3 in [lot.entrance.segment.finish,point(lot,lot.asset.get_meta("site_entrance")),point(lot,Vector3(6.5,1,10.9))]:
		if not check(await walk_to(game,target),"player physically walks from spawn toward counter: "+str(target)):
			await photograph("walk-failed");await finish();return
	game.camera.look_at(game.trader.anchor+Vector3.UP*1.45)
	if not check(game.trader.try_open(game.world_interaction.hit(game)),"ordinary scene picking opens trader"):await finish();return
	check(game.quests.store.snapshot().introduction==2 and game.trader.ui.quest_panel.visible,"talk completes the introduction and opens Quests")
	await photograph("quests")
	game.trader.ui.select_mode("Trade")
	check(game.trader.ui.trade_panel.visible and not game.trader.ui.quest_panel.visible,"Trade remains independently available")
	await photograph("trade");game.trader.ui.select_mode("Quests")
	if not check(await wait_for(func():return game.world_vehicle.scene_ready(),20),"service car asset loads"):await finish();return
	var before:Dictionary={}
	for item:int in [6,8,223,Trade.CURRENCY]:before[item]=Trade.count(game.player_hud.inventory,item)
	game.trader.ui.quest_button.pressed.emit()
	if not check(ride.state.phase==ride.BOARDING and ride.state.expedition,"quest button reserves a free expedition: "+game.trader.ui.quest_error):await finish();return
	check(Trade.count(game.player_hud.inventory,6)==before[6]+1 and Trade.count(game.player_hud.inventory,8)==before[8]+1 and Trade.count(game.player_hud.inventory,223)==before[223]+180,"trader grants one torch, one automatic rifle and 180 rounds")
	check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==before[Trade.CURRENCY],"expedition does not charge coins")
	check(game.player_hud.active_item==8 and game.player_hud.active_slot>=0 and game.player_hud.active_slot<10 and game.equipped_tool==8,"trader handoff automatically equips the gifted Ranger on the toolbelt")
	await depart(game,ride)

func depart(game:Node,ride:Node)->void:
	if not check(await watch(func():return ride.state.seated or ride.navigator.state(1)=="blocked",120) and ride.state.seated,"trader walks from shop to the service car"):await photograph("driver-walk-failed");await finish();return
	if not check(await walk_player_to_car(game,ride),"player walks to the parked car"):await photograph("car-walk-failed");await finish();return
	if not check(game.world_vehicle.enter(game,ride.identity()),"normal car interaction boards the player as passenger"):board_diagnostic(game,ride);await finish();return
	var departed:Vector3=ride.car.position
	if not check(await watch(func():return ride.car.position.distance_to(departed)>12,40),"actual wheel physics starts the expedition"):await photograph("departure-failed");await finish();return
	await seat_photograph(game,ride)
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var({"vehicle":ride.identity(),"quests":game.quests.store.capture_storage_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot()})
	await finish()

func point(lot:Dictionary,local:Vector3)->Vector3:
	return Vector3(lot.origin)+preload("res://addons/exploration/cave_layouts.gd").turn(local,lot.rotation)

func walk_to(game:Node,target:Vector3)->bool:
	for tick in 900:
		await physics_frame;game.app_focused=true
		if not combat_targets.is_empty() and tick%60==0:
			if not await shoot_visible(game):return false
		for entry:Dictionary in game.doors.types.values():
			for identity:int in entry.collection.get_ids():
				var pose:PackedFloat32Array=entry.collection.get_instance(identity)
				if pose.size()==12 and Vector3(pose[3],pose[7],pose[11]).distance_to(game.player.position)<3 and not entry.state.is_open(identity) and not entry.state.is_moving(identity):entry.state.animate_toggle(entry.collection,identity,AABB())
		var offset:Vector3=target-game.player.position;offset.y=0
		if offset.length()<.2:game.player.velocity=Vector3.ZERO;return true
		game.player.velocity=game.movement.walking_velocity(offset.normalized(),game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
		game.movement.move_grounded(game.player,1.0/60)
		game.camera.look_at(target+Vector3.UP*1.4)
	print("WALK_FAILED ",{"position":game.player.position,"target":target});return false

func trader_approach(game:Node,interact:bool=true)->bool:
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",Recipe.DEFAULTS))
	while worker.is_alive():await process_frame
	var planned:Dictionary=worker.wait_to_finish();var lot:Dictionary={}
	if not planned.get("ok",false):return false
	for district:Dictionary in planned.sites:
		for candidate:Dictionary in district.lots:
			if candidate.asset.has_meta("trader_anchor"):lot=candidate;break
	if lot.is_empty():return false
	var path:Dictionary=lot.entrance.segment
	var roadside:Vector3=Vector3(path.finish).lerp(path.start,minf(.5,3.0/Vector3(path.finish).distance_to(path.start)))
	for target:Vector3 in [roadside,point(lot,lot.asset.get_meta("site_entrance")),point(lot,Vector3(6.5,1,10.9))]:
		if not await walk_to(game,target):return false
	game.camera.look_at(game.trader.anchor+Vector3.UP*1.45)
	return not interact or game.trader.try_open(game.world_interaction.hit(game))

func shoot_visible(game:Node)->bool:
	for tick in 900:
		var target:CharacterBody3D=null;var contact:=Vector3.INF;var nearest:=18.0
		for actor:CharacterBody3D in game.zombies.residents:
			if not actor.alive or actor.get_meta("world_zombie_id",0) not in combat_targets:continue
			var bone:int=actor.skeleton.find_bone(actor.PARTS.torso.bone)
			var position:Vector3=(actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(bone)).origin+Vector3.UP*.12
			var distance:float=game.camera.global_position.distance_to(position)
			if distance>=nearest:continue
			var hit:Dictionary=game.zombies.pick(game.camera.global_position,position,[game.player.get_rid()])
			if hit.is_empty() or hit.zombie!=actor:continue
			var solid:Dictionary=game.structures.blocks.raycast_scene(game.camera.global_position,position,15,[game.player.get_rid()],true)
			if not solid.is_empty() and game.camera.global_position.distance_to(solid.position)<game.camera.global_position.distance_to(hit.position)-.01:continue
			target=actor;contact=position;nearest=distance
		if target==null:return true
		game.camera.look_at(contact)
		if game.combat.state.get_rounds(8)==0:
			if game.combat.rounds_in_bag(8)==0:print("EXPEDITION_AMMO_EXHAUSTED shots=",game.combat.shots);return false
			if game.combat.reload_slot<0:game.combat.reload()
		else:game.combat.fire()
		await physics_frame
	print("EXPEDITION_COMBAT_TIMEOUT ",game.combat.can_use()," ",game.equipped_tool);return false

func complete_mine(game:Node,ride:Node)->void:
	if stage=="clear_resume":
		if not check(ride.state.phase==ride.ARRIVED and not game.world_vehicle.driving and game.quests.store.snapshot().introduction==3,"saved mine exploration resumes with trader waiting"):await finish();return
		await explore_mine(game,ride);return
	if not check(ride.state.phase==ride.IDLE and game.quests.store.snapshot().introduction==3,"unfinished expedition can be revisited from home"):await finish();return
	if not check(await trader_approach(game),"player walks back to trader and opens Quests"):await finish();return
	var before:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	game.trader.ui.quest_button.pressed.emit()
	if not check(ride.state.phase==ride.BOARDING and game.player_hud.inventory.capture_storage_snapshot()==before,"revisit reserves a free ride without duplicating supplies"):await finish();return
	if not check(await watch(func():return ride.state.seated or ride.navigator.state(1)=="blocked",120) and ride.state.seated,"trader returns to the same car"):await finish();return
	if not check(await walk_player_to_car(game,ride) and game.world_vehicle.enter(game,ride.identity()),"player physically reboards the service car"):await finish();return
	if not check(await watch(func():return ride.state.phase==ride.ARRIVED,180),"revisit reaches the mine stop"):await finish();return
	game.world_vehicle.exit_vehicle(game)
	if not check(game.world_vehicle.passenger==null,"player exits for mine exploration"):await finish();return
	await explore_mine(game,ride)

func explore_mine(game:Node,ride:Node)->void:
	var site:Dictionary=game.quests.store.snapshot().location
	combat_targets=game.zombies.population.store.authored_identities(site.residents)
	if not check(combat_targets.size()==13 and not combat_targets.has(0),"quest resolves all thirteen generated mine residents"):await finish();return
	game.combat.action_input_owned=func()->bool:return true
	await process_frame
	check(game.player_hud.equip_item(8) and game.equipped_tool==8,"supplied automatic rifle equips normally")
	for tick in 60:await physics_frame
	if stage!="clear_resume" and not check(await walk_to(game,site.marker),"player follows the surveyed road-to-mine approach"):await photograph("mine-approach-failed");await finish();return
	var layouts=preload("res://addons/exploration/cave_layouts.gd")
	if not check(await walk_to(game,Vector3(site.origin)+layouts.turn(Vector3(.5,0,2),site.rotation)),"player approaches the personnel door"):await finish();return
	game.camera.look_at(Vector3(site.origin)+layouts.turn(Vector3(.5,1,4.5),site.rotation))
	var door:Dictionary=game.doors.aimed(game.structures.blocks.raycast_scene(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3,7,[game.player.get_rid()],true))
	var already_open:=false
	for identity:int in game.doors.collection.get_ids():
		var pose:PackedFloat32Array=game.doors.collection.get_instance(identity)
		if Vector3(pose[3],pose[7],pose[11]).distance_to(game.player.position)<4 and game.doors.state.is_open(identity):already_open=true
	if not check(already_open or not door.is_empty(),"mine entrance is open or reachable through normal picking"):await photograph("door-pick-failed");await finish();return
	if not already_open:
		check(game.doors.try_interact(),"normal interaction opens the mine entrance")
	for tick in 90:await physics_frame
	var locals:Array=[Vector3(.5,0,7),Vector3(.5,0,12.5),Vector3(9.5,0,12.5),Vector3(.5,0,12.5),Vector3(.5,0,22.5),Vector3(9,0,22.5),Vector3(.5,0,22.5),Vector3(.5,0,32.5),Vector3(-3.5,0,36.5),Vector3(-15.5,0,36.5),Vector3(-19.5,0,32.5),Vector3(-19.5,0,20.5),Vector3(-15.5,0,16.5),Vector3(-3.5,0,16.5),Vector3(.5,0,20.5),Vector3(.5,0,32.5),Vector3(.5,0,43),Vector3(.5,0,54)]
	for local:Vector3 in locals:
		var target:Vector3=Vector3(site.origin)+preload("res://addons/exploration/cave_layouts.gd").turn(local,site.rotation)
		if not check(await walk_to(game,target) and absf(game.player.position.y-target.y)<.5,"walk and fire through authored mine route "+str(local)):await photograph("mine-combat-failed");await finish();return
	if not check(await shoot_visible(game) and await wait_for(func():return game.quests.store.snapshot().phase==4,8),"real rifle impacts clear all thirteen residents and finish the quest"):await photograph("mine-incomplete");await finish();return
	print("EXPEDITION_COMBAT shots=",game.combat.shots," rounds_left=",game.combat.rounds_in_bag(8)+game.combat.state.get_rounds(8))
	await photograph("mine-cleared");combat_targets.clear()
	for local:Vector3 in [Vector3(.5,0,43),Vector3(.5,0,32.5),Vector3(.5,0,22.5),Vector3(.5,0,12.5),Vector3(.5,0,7),Vector3(.5,0,2),Vector3(.5,0,-5.5)]:
		if not check(await walk_to(game,Vector3(site.origin)+preload("res://addons/exploration/cave_layouts.gd").turn(local,site.rotation)),"physical mine exit "+str(local)):await finish();return
	if not check(await walk_player_to_car(game,ride) and game.world_vehicle.enter(game,ride.identity()),"completed player returns to the waiting car"):await finish();return
	if not check(await watch(func():return ride.state.phase==ride.HOME_ARRIVED,240),"completed expedition drives home"):await finish();return
	game.world_vehicle.exit_vehicle(game)
	await claim_reward(game,ride)

func claim_reward(game:Node,ride:Node)->void:
	if not check(await trader_approach(game,false),"player clears the vehicle exit and walks to the counter"):await finish();return
	if not check(await watch(func():return ride.state.phase==ride.IDLE,120),"trader returns to counter after completed expedition"):
		print("RETURN_WALK_FAILED ",ride.navigator.diagnostics(1));await photograph("return-counter-failed");await finish();return
	if not check(await trader_approach(game),"player returns to claim the completed contract"):await finish();return
	game.trader.ui.quest_button.pressed.emit()
	if not check(game.quests.store.snapshot().introduction==4,"ordinary Quests button pays and completes introduction"):await finish();return
	await photograph("quest-reward")
	FileAccess.open(folder.path_join("completed.bin"),FileAccess.WRITE).store_var({"vehicle":ride.identity(),"quests":game.quests.store.capture_storage_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot()})
	await finish()

func finish()->void:
	if physics_frame.is_connected(update_population):physics_frame.disconnect(update_population)
	print("FRONTIER_EXPEDITION_WORLD checks=",checks," failures=",failures," stage=",stage)
	await super.finish()

func update_population()->void:
	if not game_ready():return
	var game:=current_scene
	if not game.world_vehicle.driving:
		game.terrain.focus=game.player.position;game.terrain.require_collision=true
	game.zombies.update(1.0/Engine.physics_ticks_per_second,game.player.global_position,not game.player_view.entry.active and not game.loading_active and not game.shutdown_requested and game.terrain.world_ready and not game.terrain.pending_edit and not game.session_menu.pauses_world() and not game.player_hud.inventory_open and not game.world_vehicle.driving and game.app_focused,not game.fly)
