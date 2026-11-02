# SPDX-License-Identifier: 0BSD
extends SceneTree

const QuestWorld=preload("res://addons/player_runtime/quest_world.gd")
const TraderPanel=preload("res://addons/player_runtime/trader_panel.gd")
const Rally=preload("res://addons/player_runtime/quest_rally.gd")
var checks:=0
var failures:=0

class Originals extends RefCounted:
	var revision:=1
	var queries:=0
	var keys: Array=[1]
	func state()->Dictionary:return {"owner":1,"revision":revision}
	func has_baseline_reference(key:int,_definition:PackedByteArray)->bool:
		queries+=1;return key in keys

class Ride extends RefCounted:
	func spawn_position()->Vector3:return Vector3(2,40,2)

class Merchant extends Node:
	var near:=true
	var ride:=Ride.new()
	func reachable()->bool:return near

class Guide extends Node:
	var last:Dictionary={}
	func track(value:Dictionary)->bool:last=value;return true
	func refresh()->void:pass

class Notices extends Node:
	var notices:Array=[]
	func quest_added(title:String)->void:notices.append(title)

class Game extends Node:
	var player:Dictionary={"global_position":Vector3.ZERO}
	var terrain:Dictionary={"backend":{"readonly_snapshot":false},"epoch":1,"changed_since_save":false}
	var temporary_world:=false
	var persistence:Dictionary={"location_baselines":Originals.new()}
	var trader:=Merchant.new()
	var destination_guide:=Guide.new()
	var player_notices:=Notices.new()

func _initialize()->void:run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func location(key:int)->Dictionary:
	var point:=Vector3(key*20,40,100)
	return {"key":key,"layout":"coal_mine" if key==1 else "mine_test","title":"Mine %d"%key,"origin":Vector3i(point),"rotation":0,"marker":point+Vector3(2,0,-1),"bounds":AABB(point,Vector3(8,5,8)),"residents":PackedInt64Array([100+key]),"containers":PackedInt64Array([200+key]),"coins":20,"xp":80}

func run()->void:
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for item:int in [6,8,223,601]:inventory.register_item(item,1000000)
	var quest:=QuestWorld.new();var game:=Game.new();quest.game=game
	quest.store=ClassDB.instantiate("NativeQuestLog");quest.store.configure(inventory,601)
	check(quest.store.register_locations(1703,[location(1),location(2)]).ok,"two native location definitions")
	var panel:=TraderPanel.new();panel.quests=quest;root.add_child(panel)
	panel.opened=true;panel.permitted=game.trader.reachable
	panel.refresh_quests()
	check(panel.quest_offers.item_count==1 and not panel.quest_button.disabled,"trader lists only locations with preserved originals")
	check(panel.quest_offers.get_item_text(0).contains(" m S") and panel.quest_offers.get_item_tooltip(0).contains("Map coordinates"),"offers identify distance, compass bearing and map position")
	var count:int=game.persistence.location_baselines.queries
	for repeat in 10:panel.refresh_quests()
	check(game.persistence.location_baselines.queries==count,"repeated UI refresh reuses metadata without rereading originals")
	game.trader.near=false
	check(not quest.accept(1).ok and quest.store.snapshot().phase==0,"remote acceptance rejected")
	game.trader.near=true
	check(not quest.accept(2).ok,"UI cannot accept a missing baseline through a stale selection")
	panel.quest_button.pressed.emit()
	check(quest.store.snapshot().phase==1 and quest.store.snapshot().key==1,"actual trader button reserves the selected native quest")
	check(game.player_notices.notices==["Mine 1"] and game.destination_guide.last.title.contains("Start at ?"),"reservation posts quest notice and map/compass destination")
	check(panel.quest_abandon.visible and not panel.quest_button.visible and quest.description().contains("replacing"),"reserved quest explains scoped replacement and exposes abandonment")
	var reserved:PackedByteArray=quest.store.capture_storage_snapshot()
	panel.quest_abandon.pressed.emit()
	check(quest.store.snapshot().phase==0 and panel.quest_offers.visible,"actual abandon button returns to offers")
	game.persistence.location_baselines.keys=[1,2];game.persistence.location_baselines.revision+=1
	panel.refresh_quests()
	check(panel.quest_offers.item_count==2,"new originals invalidate offer cache")
	check(quest.store.restore_storage_snapshot(reserved) and quest.marker().title.contains("Start at ?"),"saved reservation restores rally guidance")
	var reset:Dictionary=quest.store.begin_reset(quest.store.snapshot().revision)
	check(quest.store.finish_reset(reset.cycle,true,quest.store.snapshot().revision).ok,"native reset activates the reservation")
	quest.store.advance_search(location(1).marker,1000)
	check(quest.marker().get("area",false),"arrived active quest switches from waypoint to area")
	quest.store.record_defeated(101,reset.cycle);panel.refresh_quests()
	check(panel.quest_button.text=="Collect reward" and not panel.quest_button.disabled,"repeatable completion exposes reward without requiring a car")
	check(quest.marker().position==Vector3(2,40,2),"completed repeatable quest points back to trader")
	game.temporary_world=true
	quest.store.abandon(quest.store.snapshot().revision)
	check(quest.offers().is_empty(),"temporary worlds do not offer destructive resets")
	game.temporary_world=false;game.terrain.backend.readonly_snapshot=true
	check(quest.offers().is_empty(),"readonly worlds do not offer destructive resets")
	game.terrain.backend.readonly_snapshot=false
	quest.store=ClassDB.instantiate("NativeQuestLog");quest.store.configure(inventory,601)
	quest.store.register_locations(1703,[location(1),location(2)]);quest.offer_token=[]
	check(quest.store.initialize_introduction(quest.store.snapshot().revision).ok,"fixture starts ordinary trader introduction")
	quest.store.talk_to_trader(quest.store.snapshot().revision)
	quest.store.accept_first_visit(1,inventory,quest.store.snapshot().revision,inventory.snapshot().revision)
	quest.store.record_defeated(101,quest.store.snapshot().cycle)
	var inbox:RefCounted=ClassDB.instantiate("NativeRewardInbox")
	var progression:RefCounted=ClassDB.instantiate("NativePlayerProgression");progression.configure(PackedInt64Array([1,5,50]))
	check(quest.store.claim(inbox,progression,quest.store.snapshot().revision).ok and quest.store.snapshot().introduction==4,"fixture completes introductory coal quest through native rewards")
	check(quest.accept(2).ok and quest.description().begins_with("Mine 2") and quest.marker().title.begins_with("Mine 2"),"completed introduction no longer masks a later repeatable quest")
	for rotation in 4:
		var place:=location(1);place.rotation=rotation;place.marker=place.bounds.get_center()
		var point:=Rally.anchor(place)
		check(not place.bounds.grow(1.99).has_point(point),"rally is outside reset exclusion at rotation %d"%rotation)
	check(Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-2),{}),"near unobstructed rally can be targeted")
	check(not Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-2),{"position":Vector3(0,0,-1)}),"wall before rally prevents interaction")
	check(not Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-4),{}) and not Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,2),{}) and not Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(1,0,-2),{}),"distant, behind-camera and off-aim rallies reject interaction")
	check(Rally.ray_matches(Vector3.ZERO,Vector3.FORWARD,Vector3(0,0,-2),{"position":Vector3(0,0,-2.5)}),"geometry behind rally does not hide its action")
	panel.free();quest.resetter.free();quest.rally.free();quest.free()
	game.trader.free();game.destination_guide.free();game.player_notices.free();game.free()
	print("QUEST_OFFERS checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
