# SPDX-License-Identifier: 0BSD
extends RefCounted
const Capture=preload("res://addons/world_runtime/location_capture.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var test:SceneTree
var game:Node
var location:Dictionary
var checkpoint_corpses:=PackedByteArray()

class UncapturedInteraction:
	extends "res://demo/world_interaction.gd"
	func available(owner:Node)->bool:
		return owner._model_edit_available() and not owner.fly and not owner.session_menu.visible_ui()

func check(value:bool,label:String)->bool:
	return test.check(value,label)

func terrain_bytes()->Array:
	var result:Array=[]
	for tile:Array in Capture.tiles(Vector3i(location.bounds.position),Vector3i(location.bounds.size)+Vector3i.ONE):
		result.append(Capture.patch(game.terrain.backend.native,"field",tile))
	return result

func corpse_bytes()->PackedByteArray:
	return Capture.patch(game.corpse_loot.store,"corpse",[game.zombies.population.store.authored_identities(location.residents),location.residents])

func picture(name:String,point:Vector3)->void:
	var observer:=Camera3D.new();game.add_child(observer)
	observer.global_position=point+Vector3(-4,3,4);observer.look_at(point);observer.current=true
	await test.process_frame
	await test.photograph(name)
	observer.free();game.camera.current=true

func contacts()->PackedFloat32Array:
	var result:=PackedFloat32Array()
	var center:Vector3=location.bounds.get_center()+Vector3(0,-4,0)
	for offset:Vector3 in [Vector3.ZERO,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var start:Vector3=center+offset+Vector3.UP*3
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,start-Vector3.UP*8,1))
		result.append(-999 if hit.is_empty() else snappedf(hit.position.y,.001))
	return result

func prepare_intro()->bool:
	var store:RefCounted=game.quests.store
	var state:Dictionary=store.snapshot()
	if state.introduction==1:
		if not check(store.talk_to_trader(state.revision).ok,"fixture advances existing introduction"):return false
		state=store.snapshot()
	if state.introduction==2:
		var coal:Dictionary={}
		for entry:Dictionary in store.get_locations():
			if entry.layout=="coal_mine":coal=entry
		if not check(not coal.is_empty() and store.accept_first_visit(coal.key,game.player_hud.inventory,state.revision,game.player_hud.inventory.snapshot().revision).ok,"fixture accepts ordinary introductory expedition"):return false
		state=store.snapshot()
	if state.phase==3:
		for anchor:int in state.location.residents:store.record_defeated(anchor,state.cycle)
		state=store.snapshot()
	if state.phase==4:
		if not check(store.claim(game.player_hud.reward_inbox,game.player_hud.progression,state.revision).ok,"fixture completes prior quest before testing repeatable reset"):return false
	elif state.phase==1:
		if not check(store.abandon(state.revision).ok,"fixture clears prior travel reservation"):return false
	return store.snapshot().phase==0

func walk_to(target:Vector3)->bool:
	for tick in 900:
		await test.physics_frame;game.app_focused=true
		var offset:Vector3=target-game.player.position;offset.y=0
		if offset.length()<.18:game.player.velocity=Vector3.ZERO;return true
		game.player.velocity=game.movement.walking_velocity(offset.normalized(),game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
		game.movement.move_grounded(game.player,1.0/60)
		game.terrain.focus=game.player.position
	print("QUEST_TRADER_WALK_FAILED ",JSON.stringify({"position":game.player.position,"target":target}));return false

func reserve_at_trader()->bool:
	var worker:=Thread.new()
	var generator=preload("res://addons/world_runtime/world_generation_plan.gd")
	worker.start(generator.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS))
	while worker.is_alive():await test.process_frame
	var planned:Dictionary=worker.wait_to_finish();var lot:Dictionary={}
	if not check(planned.get("ok",false),"cached ordinary plan resolves trader approach"):return false
	for district:Dictionary in planned.sites:
		for candidate:Dictionary in district.lots:
			if candidate.asset.has_meta("trader_anchor"):lot=candidate;break
	if not check(not lot.is_empty(),"ordinary trader building has an authored approach"):return false
	var anchor:Transform3D=lot.asset.get_meta("trader_anchor")
	if not check((Vector3(lot.origin)+anchor.origin).distance_to(game.trader.anchor)<.01,"approach matches the saved world trader identity"):return false
	game.teleport(lot.entrance.segment.finish+Vector3.UP)
	if not check(await test.wait_for(func()->bool:return not game.loading_active and is_instance_valid(game.trader.actor),120),"trader activates at its real shop with ready collision"):return false
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	game.player.position=lot.entrance.segment.finish+Vector3.UP*.04
	game.camera.position=Vector3(0,1.65,0);game.camera.rotation=Vector3.ZERO
	for entry:Dictionary in game.doors.types.values():
		for identity:int in entry.collection.get_ids():
			var pose:PackedFloat32Array=entry.collection.get_instance(identity)
			if pose.size()==12 and lot.bounds.grow(1).has_point(Vector3(pose[3],pose[7],pose[11])) and not entry.state.is_open(identity):entry.state.animate_toggle(entry.collection,identity,AABB())
	var layouts=preload("res://addons/exploration/cave_layouts.gd")
	for local:Vector3 in [lot.asset.get_meta("site_entrance"),Vector3(6.5,1,10.9)]:
		if not check(await walk_to(Vector3(lot.origin)+layouts.turn(local,lot.rotation)),"actual player walks from street through shop to counter"):return false
	game.camera.look_at(game.trader.actor.global_position+Vector3.UP*1.45);game.app_focused=true
	var target:Dictionary=game.world_interaction.hit(game)
	if not check(game.world_interaction.describe(game,target)=="E · Trade supplies" and game.trader.try_open(target),"normal native scene picking opens the actual trader"):return false
	var ui:Node=game.trader.ui;ui.select_mode("Quests")
	var selected:=-1
	for index in ui.quest_offers.item_count:
		if ui.quest_offers.get_item_metadata(index)==location.key:selected=index;break
	if not check(selected>=0,"trader offers the generated mine with its preserved original"):return false
	var offer_text:String=ui.quest_offers.get_item_text(selected)
	check((offer_text.contains(" m") or offer_text.contains(" km")) and ui.quest_offers.get_item_tooltip(selected).contains("Map coordinates:"),"packaged trader distinguishes destinations by distance and map position")
	ui.quest_offers.select(selected)
	await test.photograph("repeatable_trader_offers")
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
	var progression:PackedByteArray=game.player_hud.progression.capture_storage_snapshot()
	ui.quest_button.pressed.emit()
	var state:Dictionary=game.quests.store.snapshot()
	if not check(state.phase==1 and state.key==location.key and not game.quests.resetter.busy,"ordinary trader button reserves only, without resetting at the shop"):return false
	check(inventory==game.player_hud.inventory.capture_storage_snapshot() and progression==game.player_hud.progression.capture_storage_snapshot(),"acceptance gives no unearned inventory or XP")
	check(ui.quest_text.text.contains("replacing") and game.quests.marker().title.contains("Start at ?"),"trader discloses local replacement and tracks the start marker")
	await test.photograph("repeatable_trader_reserved")
	var close_event:=InputEventKey.new();close_event.pressed=true;close_event.physical_keycode=KEY_E
	ui._input(close_event)
	check(not ui.opened and not game.player_hud.inventory_open,"E closes trader and restores gameplay UI state")
	return true

func wait_reset(cancel_after:int=-1)->bool:
	var reset:Node=game.quests.resetter
	var observed_at:=Time.get_ticks_usec()
	var deadline:=Time.get_ticks_msec()+180000
	var last_phase:=""
	var next_report:=Time.get_ticks_msec()+10000
	while reset.busy and Time.get_ticks_msec()<deadline:
		if reset.phase!=last_phase:
			last_phase=reset.phase;print("LIVE_RESET_PHASE ",last_phase," elapsed_us=",Time.get_ticks_usec()-observed_at)
			if last_phase=="preparing":checkpoint_corpses=corpse_bytes()
		if cancel_after>=0 and reset.batch!=null and reset.batch.status().applied>=cancel_after:
			reset.cancel();cancel_after=-1
		if Time.get_ticks_msec()>=next_report:
			next_report=Time.get_ticks_msec()+10000
			test.save_diagnostic()
			print("RESET_SAVE_ADMISSION ",JSON.stringify({"terrain_processing":game.terrain.is_processing(),"terrain_mode":game.terrain.process_mode,"world_processing":game.is_processing(),"status":game.terrain.backend.status(),"publication":game.terrain.backend.publication_pending()}))
			print("LIVE_RESET_WAIT ",JSON.stringify({"phase":reset.phase,"water":game.lakes.statistics(),"queue":game.terrain.backend.diagnostic_queue_snapshot(),"pager":game.model_paging.operation,"error":game.terrain.latest_error}))
		await test.process_frame
	print("LIVE_RESET_RESULT ",JSON.stringify(reset.last_result))
	if reset.busy:
		print("LIVE_RESET_TIMEOUT ",JSON.stringify({"phase":reset.phase,"batch":reset.batch.status() if reset.batch!=null else {},"water":game.lakes.statistics(),"queue":game.terrain.backend.diagnostic_queue_snapshot(),"error":game.terrain.latest_error}))
	return not reset.busy

func run(owner:SceneTree)->void:
	test=owner;game=test.game
	for entry:Dictionary in game.quests.store.get_locations():
		if entry.layout=="survey_mine":location=entry
	if not check(not location.is_empty(),"live test uses actual generated survey mine"):return
	var expected_path:String=test.folder.path_join("live_expected.bin")
	var bounds:AABB=location.bounds
	var outside:Vector3=bounds.position+Vector3(-4,bounds.size.y-2,bounds.size.z*.5)
	game.teleport(outside,outside.y)
	if not check(await test.wait_for(test.game_ready,120),"normal streaming prepares mine from outside its reset bounds"):return
	game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
	if "--baseline-reopen" in OS.get_cmdline_user_args():
		var saved:Dictionary=FileAccess.open(expected_path,FileAccess.READ).get_var()
		check(terrain_bytes()==saved.terrain,"fresh process retains exact restored field")
		check(corpse_bytes()==saved.corpses,"fresh process retains scoped corpse removal")
		check(game.quests.store.snapshot().phase==3,"fresh process retains activated reset quest")
		check(game.player_hud.inventory.capture_storage_snapshot()==saved.inventory,"fresh process preserves player inventory across reset")
		check(game.player_hud.progression.capture_storage_snapshot()==saved.progression,"fresh process preserves player progression across reset")
		check(Capture.patch(game.structures.blocks,"cell",[saved.outside_cell,Vector3i.ONE])==saved.outside_block,"fresh process retains outside block")
		check(contacts()==saved.contacts,"fresh process collision matches locally published restored terrain")
		check(await test.leave(),"fresh reset checkpoint closes normally");return
	if not prepare_intro():return
	var fixture_inventory:RefCounted=game.player_hud.inventory
	var fixture_slots:Array=fixture_inventory.snapshot().slots
	for index in range(10,fixture_slots.size()):
		if fixture_slots[index].count>0:fixture_inventory.consume(index,fixture_slots[index].count,fixture_inventory.snapshot().revision)
	game.player_hud.deliver_mining_rewards()
	if not check(game.player_hud.reward_inbox.get_pending().is_empty(),"owned fixture has room for ordinary mining rewards"):return
	var original:Dictionary=game.persistence.location_baselines.load_baseline(location.key,Capture.definition(location))
	if not check(original.ok,"live reset has a real immutable original"):return
	var original_field:Array=Capture.unpack(original.sections.terrain,"terrain",bounds).records
	var original_corpse:PackedByteArray=Capture.unpack(original.sections.corpses,"corpses",bounds).records[0]
	var store:RefCounted=game.quests.store
	if "--verify-trader-offer" in OS.get_cmdline_user_args():
		if not await reserve_at_trader():return
		game.teleport(outside,outside.y)
		if not check(await test.wait_for(test.game_ready,120),"normal fast travel returns to the selected mine"):return
		game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
	elif not check(store.accept(location.key,store.snapshot().revision).ok,"repeatable reservation uses generated location"):return
	var reset:Node=game.quests.resetter
	var prior:Vector3=game.player.global_position
	game.player.global_position=bounds.get_center()
	check(not reset.begin().ok and not reset.busy,"player inside reset volume rejects without mutation")
	game.player.global_position=prior
	var previous_corpses:PackedByteArray=game.corpse_loot.store.capture_corpse_snapshot()
	var foreign:int=game.corpse_loot.store.create_corpse(bounds.get_center(),0,1703,0,0)
	check(foreign>0 and not reset.begin().ok,"dormant unrelated corpse blocks resetting occupied location")
	check(game.corpse_loot.store.restore_corpse_snapshot(previous_corpses),"fixture removes only its temporary foreign corpse")
	var point:Vector3=bounds.get_center()+Vector3(0,-4,0)
	var edit_messages:Array=[]
	var record_message:=func(message:String):edit_messages.append(message)
	game.terrain.message_changed.connect(record_message)
	var accepted:bool=game.terrain.edit(Codec.brush(point,point,2,0,false,3),point-Vector3.ONE*7,point+Vector3.ONE*7)
	print("LIVE_EDIT_ADMISSION ",JSON.stringify({"accepted":accepted,"pending":game.terrain.pending_edit,"ready":game.terrain.world_ready,"closing":game.terrain.closing,"error":game.terrain.latest_error,"messages":edit_messages,"rewards":game.player_hud.reward_inbox.get_pending()}))
	game.terrain.message_changed.disconnect(record_message)
	if not check(accepted and await test.wait_for(func()->bool:return not game.terrain.pending_edit,60),"ordinary terrain edit publishes inside the location"):return
	var edited:=terrain_bytes()
	if not check(edited!=original_field,"excavation changes actual native field from original"):return
	var edited_contacts:=contacts()
	await picture("mine_edited",point)
	var inside_cell:=Vector3i(bounds.position)+Vector3i(3,3,3)
	var outside_cell:=Vector3i(bounds.position)+Vector3i(-3,3,3)
	check(game.structures.blocks.set_cells(PackedInt32Array([inside_cell.x,inside_cell.y,inside_cell.z,1,outside_cell.x,outside_cell.y,outside_cell.z,1])),"player blocks added inside and outside selected location")
	var outside_block:=Capture.patch(game.structures.blocks,"cell",[outside_cell,Vector3i.ONE])
	var chest:int=location.containers[0]
	var containers:RefCounted=game.storage.store
	containers.damage_lock(chest,10000,containers.snapshot(chest).store_revision)
	var inventory:RefCounted=game.player_hud.inventory
	var chest_state:Dictionary=containers.snapshot(chest)
	for index in chest_state.slots.size():
		if chest_state.slots[index].get("item",0)>0:
			check(containers.withdraw(chest,inventory,index,1,inventory.snapshot().revision,chest_state.store_revision).ok,"player loots a real mine supply before reset")
			break
	var before_supplies:=Capture.patch(containers,"container",[location.containers])
	var ids:PackedInt64Array=game.zombies.population.store.authored_identities(location.residents)
	var resident:Dictionary=game.zombies.population.store.resident(ids[0])
	game.zombies.retire_location(ids)
	await test.process_frame
	var vitals:PackedByteArray=resident.vitals.duplicate();vitals.encode_float(0,0)
	check(resident.state==2 or game.zombies.population.store.update_resident(ids[0],resident.position,resident.yaw,vitals),"owned sleeper is dead before reset")
	var corpse:=0
	for identity:int in game.corpse_loot.store.corpse_ids():
		if game.corpse_loot.store.corpse(identity).resident==ids[0]:corpse=identity;break
	if corpse==0:corpse=game.corpse_loot.store.create_corpse(resident.position,resident.yaw,1703,ids[0],resident.anchor)
	check(corpse>0,"owned corpse exists before reset")
	var corpse_region:=AABB(resident.position-Vector3(2,1,2),Vector3(4,3,4))
	if not check(await test.wait_for(func()->bool:return game._actor_collision_ready(corpse_region),30),"normal collision publication prepares corpse residency"):return
	game.corpse_loot.clock=0
	game.corpse_loot.update(0,resident.position,true)
	game.corpse_loot.update(0,resident.position,false)
	check(game.corpse_loot.active.has(corpse),"owned corpse has an actual scene body before reset")
	print("LIVE_CORPSE_RESIDENCY ",JSON.stringify({"id":corpse,"position":str(resident.position),"active":game.corpse_loot.active.keys(),"nearby":game.corpse_loot.store.nearby_corpses(resident.position,80,PackedInt64Array())}))
	game.corpse_loot.capture()
	var player_bytes:PackedByteArray=inventory.capture_storage_snapshot()
	var progression:PackedByteArray=game.player_hud.progression.capture_storage_snapshot()
	var started:Dictionary=reset.begin();print("LIVE_RESET_BEGIN ",JSON.stringify(started))
	if not check(started.ok,"live reset admits outside player after edits"):return
	if not check(await wait_reset(3) and not reset.last_result.ok and reset.phase=="cancelled","cancel midway reloads verified pre-reset checkpoint"):return
	if not check(await test.wait_for(test.game_ready,120),"cancel recovery returns to ready gameplay"):return
	check(terrain_bytes()==edited,"cancel recovers exact edited terrain")
	check(not checkpoint_corpses.is_empty() and corpse_bytes()==checkpoint_corpses,"cancel recovers exact corpse pose captured by the verified checkpoint")
	check(store.snapshot().phase==1,"cancel retains reservation instead of activating quest")
	check(Capture.patch(containers,"container",[location.containers])==before_supplies,"cancel preserves original current supplies")
	check(Capture.patch(game.structures.blocks,"cell",[outside_cell,Vector3i.ONE])==outside_block,"cancel preserves neighboring block")
	var epoch:int=game.terrain.epoch
	var rally:Node3D=game.quests.rally
	if not check(await test.wait_for(func()->bool:return rally.visible and rally.ready_key==location.key,15),"reserved generated mine presents its question mark on ready ground"):return
	var outward:Vector3=(rally.global_position-bounds.get_center())*Vector3(1,0,1)
	outward=outward.normalized()
	game.fly=false;game.player.global_position=rally.global_position+outward*2-Vector3.UP*1.4
	game.terrain.focus=game.player.position
	if "--offset-rally-focus" in OS.get_cmdline_user_args():game.terrain.focus+=Vector3(40,0,0)
	game.camera.global_position=rally.global_position+outward*2;game.camera.look_at(rally.global_position)
	game.set_physics_process(false)
	await test.process_frame
	var interaction:=UncapturedInteraction.new()
	var aimed:Dictionary=interaction.hit(game)
	print("RALLY_AIM ",JSON.stringify({"marker":rally.global_position,"player":game.player.global_position,"target":aimed,"available":interaction.available(game)}))
	check(interaction.describe(game,aimed).contains("Start quest"),"shared native picking presents the actual rally E prompt")
	interaction.update(game,1);game.destination_guide.refresh()
	await test.photograph("quest_rally")
	if not check(interaction.interact(game) and reset.busy,"ordinary interaction dispatcher starts scoped reset without mouse capture"):return
	if "--offset-rally-focus" in OS.get_cmdline_user_args():
		var coverage=preload("res://addons/world_runtime/coverage_window.gd")
		var examined:=0;var admitted:=true
		for row in 32:
			for column in 32:
				var key:=Vector2i(column,row)
				if coverage.required(game.player.position,640,key) and not coverage.required(game.terrain.focus,640,key):
					examined+=1;admitted=admitted and game.ecosystem.admit_owner.call(key)
		check(game.loading_active and game.terrain.focus.distance_to(game.player.position)>39 and examined>0 and admitted,"paused reset admits actual-player coverage despite a 40 m terrain-focus offset")
	if not check(await wait_reset() and reset.last_result.ok,"live reset restores and compound-saves the actual mine"):return
	var playable:bool=await test.wait_for(test.game_ready,120)
	if not playable:print("RESET_LOADING_DIAGNOSTIC ",JSON.stringify({"stage":game.loading_stage_text,"work":game.loading_work_text,"player":game.player.position,"focus":game.terrain.focus,"forest":game.ecosystem.local_coverage_status(game.player.position),"boulders":game.ground_cover.boulders.local_coverage_status(game.player.position)}))
	if not check(playable,"restored geometry and contacts admit gameplay"):return
	check(game.terrain.epoch==epoch,"successful reset locally republishes terrain without whole-world reload")
	check(terrain_bytes()==original_field,"successful reset restores exact original field")
	check(corpse_bytes()==original_corpse,"successful reset removes owned corpse")
	check(not game.corpse_loot.active.has(corpse),"successful reset retires the old corpse scene body")
	check(contacts()!=edited_contacts,"restoring terrain replaces actual excavation collision")
	await picture("mine_restored",point)
	check(Capture.patch(game.structures.blocks,"cell",[outside_cell,Vector3i.ONE])==outside_block,"successful reset preserves neighboring block")
	check(inventory.capture_storage_snapshot()==player_bytes and game.player_hud.progression.capture_storage_snapshot()==progression,"reset awards no resources or experience")
	check(store.snapshot().phase==3,"successful compound publication activates encounter")
	var expected:Dictionary={"terrain":terrain_bytes(),"corpses":corpse_bytes(),"inventory":player_bytes,"progression":progression,"outside_cell":outside_cell,"outside_block":outside_block,"contacts":contacts()}
	FileAccess.open(expected_path,FileAccess.WRITE).store_var(expected)
	check(await test.leave(),"restored encounter closes through ordinary save path")
