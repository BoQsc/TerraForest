# SPDX-License-Identifier: 0BSD
extends Node
var store:RefCounted
var game:Node
var elapsed:=0.0
var tracked_key:=0
var tracked_cycle:=-1
var identities:=PackedInt64Array()
var contacts:Array=[]
var resetter=preload("res://addons/world_runtime/location_reset_live.gd").new()

func _ready()->void:
	resetter.game=game;add_child(resetter)

func prepare(owner_game:Node,persistence:RefCounted)->bool:
	game=owner_game
	store=ClassDB.instantiate("NativeQuestLog")
	if store==null or not store.configure(game.player_hud.inventory,preload("res://addons/player_runtime/trader_inventory.gd").CURRENCY):return false
	return persistence.register_component("player_quests",store.capture_storage_snapshot,restore,store,PackedByteArray())

func restore(bytes:PackedByteArray)->bool:
	var state:Dictionary=store.snapshot()
	if state.phase==2:
		if not resetter.busy or resetter.phase!="recovering" or not store.validate_snapshot(bytes):return false
		if not store.finish_reset(state.cycle,false,state.revision).ok:return false
	return store.restore_storage_snapshot(bytes)

func _process(delta:float)->void:
	elapsed-=delta
	if elapsed>0 or game.loading_active or game.shutdown_requested:return
	var milliseconds:=mini(1000,maxi(0,roundi((.5-elapsed)*1000)))
	elapsed=.5
	var state:Dictionary=store.snapshot()
	contacts.clear()
	if state.phase==3:
		if tracked_key!=state.key or tracked_cycle!=state.cycle:
			tracked_key=state.key;tracked_cycle=state.cycle
			identities=game.zombies.population.store.authored_identities(state.location.residents)
		for index in identities.size():
			var resident:Dictionary=game.zombies.population.store.resident(identities[index])
			if resident.get("anchor",0)!=state.location.residents[index]:continue
			if resident.get("state",0)==2:store.record_defeated(resident.anchor,state.cycle)
		if game.app_focused and not game.session_menu.pauses_world() and not game.player_hud.inventory_open:
			store.advance_search(game.player.global_position,milliseconds)
		var current:Dictionary=store.snapshot()
		if current.phase==3 and current.arrived:
			for index in identities.size():
				var resident:Dictionary=game.zombies.population.store.resident(identities[index])
				if resident.get("anchor",0)!=state.location.residents[index] or resident.get("state",2)!=1:continue
				var sleep:PackedByteArray=resident.sleep
				var sleeping:=not sleep.is_empty() and sleep.size()>=36 and sleep.decode_u32(32)==1
				if not sleeping or current.reveal_sleepers:contacts.append({"position":resident.position,"sleeping":sleeping,"id":resident.id})
		if store.snapshot().revision!=state.revision:game.terrain.changed_since_save=true
	game.player_hud.quests_notice.text=description()
	game.destination_guide.refresh()
	if game.trader.ui.opened:game.trader.ui.refresh_quests()

func description()->String:
	var state:Dictionary=store.snapshot()
	match int(state.introduction):
		1:return "A friendly face\nTalk to the trader. Follow the gold quest marker on your map and compass."
		2:return "Coal-mine expedition\nAsk the trader about Quests. He provides a torch, automatic rifle, ammunition and a return ride."
		3:
			return "Coal-mine expedition\nClear the mine: %d / %d zombies.\nThe trader waits at the car. Return whenever you want, even with the quest unfinished."%[state.defeated,state.target_count] if state.phase==3 else "Coal-mine expedition complete\nReturn to the trader to collect your reward. The car is waiting."
		4:return "Coal-mine expedition completed."
	if state.phase in [1,3,4]:return "%s\n%d / %d zombies cleared."%[state.location.title,state.defeated,state.target_count]
	return "No active quest."

func marker()->Dictionary:
	var state:Dictionary=store.snapshot()
	if state.introduction in [1,2] or (state.introduction==3 and state.phase==4):
		var point:Vector3=game.trader.ride.spawn_position()
		if point.is_finite():return {"position":point,"title":"Talk to trader" if state.introduction==1 else "Trader · quests","quest":true}
	if state.phase in [1,3]:
		if state.phase==3 and state.arrived:
			var bounds:AABB=state.location.bounds
			return {"position":bounds.get_center(),"radius":Vector2(bounds.size.x,bounds.size.z).length()*.5+3,"area":true,"title":"%s · Active · %d / %d cleared"%[state.location.title,state.defeated,state.target_count],"quest":true}
		return {"position":state.location.marker,"title":"%s · %d / %d"%[state.location.title,state.defeated,state.target_count],"quest":true}
	return {}

func talk()->void:
	var state:Dictionary=store.snapshot()
	if state.introduction==1 and store.talk_to_trader(state.revision).ok:game.terrain.changed_since_save=true

func start_expedition()->Dictionary:
	if not game.trader.reachable():return {"ok":false,"reason":"Approach the trader first."}
	var state:Dictionary=store.snapshot()
	if state.introduction not in [2,3]:return {"ok":false,"reason":"No expedition is available."}
	for location:Dictionary in store.get_locations():
		if location.layout!="coal_mine" or (state.introduction==3 and state.key!=location.key):continue
		var offer:Dictionary=game.trader.ride.expedition_offer(location)
		if offer.is_empty():continue
		var booked:Dictionary=game.trader.ride.book_expedition(offer,location.key)
		if booked.get("ok",false) and state.introduction==2:game.player_notices.quest_added("Coal-mine expedition")
		return booked
	return {"ok":false,"reason":"No safe connected road stop near a coal-mine entrance is available."}

func claim()->Dictionary:
	if not game.trader.reachable():return {"ok":false,"reason":"Approach the trader first."}
	var hud:Node=game.player_hud
	var result:Dictionary=store.claim(hud.reward_inbox,hud.progression,store.snapshot().revision)
	if result.ok:
		hud.deliver_mining_rewards();hud.refresh();hud.progression_changed.emit()
		if hud.resource_feed!=null:hud.resource_feed.gain_experience(result.gained,result.level)
		game.terrain.changed_since_save=true
	return result
