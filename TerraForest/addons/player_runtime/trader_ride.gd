# SPDX-License-Identifier: 0BSD
extends Node3D
## One persistent service. Native graph/motor/fleet remain movement/storage owners.
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
const Seat=preload("res://addons/player_runtime/trader_seat.gd")
const IDLE=0
const BOARDING=1
const OUTBOUND=2
const ARRIVED=3
const RETURNING=4
const HOME_WALK=5
const STOPPING=6
const HOME_ARRIVED=7
const RETURN_STOPPED=8
var host:Node3D
var game:Node3D
var store:RefCounted
var state:Dictionary={}
var planner:RefCounted
var pilot:RefCounted
var navigator:Node3D
var motor:RefCounted
var graph_revision:=-1
var graph_result:Dictionary={}
var car:RigidBody3D
var driver_view:Node3D
var passenger_view:Node3D
var command:Dictionary={}
var status_text:=""
var next_service:=0.0
var probe_remaining:=0.0
var probe_ready:=false
var probe_clear:=false
var probe_reason:=""
var next_retry:=0.0
var restore_passenger:=false
var pilot_bound:=false
var hud:CanvasLayer
var label:Label
var walk_status:="idle"
var boarding_goal:=Vector3.INF
var _last_interest:=PackedVector3Array()
var _probe_shape:=BoxShape3D.new()
var _probe_query:=PhysicsShapeQueryParameters3D.new()
var shop_doors:Array=[]
var door_retry:=0.0

func prepare(merchant:Node3D,persistence:RefCounted)->bool:
	host=merchant;game=host.game
	store=ClassDB.instantiate("NativeTraderRideState")
	if store==null:return false
	state=store.snapshot();planner=ClassDB.instantiate("NativeRoadJourney");pilot=ClassDB.instantiate("NativeRoadJourney")
	game.world_vehicle.service=self
	return persistence.register_component("trader_ride_v1",capture,restore,store,PackedByteArray())

func _ready()->void:
	process_physics_priority=-1
	navigator=ClassDB.instantiate("NativeActorNavigator");add_child(navigator);navigator.configure(1)
	navigator.set_water_depth(func(point:Vector3):return game.lakes.depth_at(point))
	motor=ClassDB.instantiate("NativePlayerMovement");motor.set_step_radius(.34)
	game.structures.changed.connect(func():navigator.invalidate())
	game.terrain.region_changed.connect(func(bounds:AABB,_revision:int):navigator.invalidate(bounds))
	game.lakes.exclusion_changed.connect(func(bounds:AABB):navigator.invalidate(bounds))
	game.world_vehicle.fleet.obstacles_changed.connect(func(bounds:AABB):navigator.invalidate(bounds))
	hud=CanvasLayer.new();hud.layer=28;add_child(hud)
	label=Label.new();label.position=Vector2(32,220);label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",Color("f4e7bf"));label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2);label.add_theme_constant_override("shadow_offset_y",2)
	hud.add_child(label)
	_probe_shape.size=Vector3(1.86,.85,3.6);_probe_query.shape=_probe_shape;_probe_query.collision_mask=15|(1<<16)|(1<<18)

func identity()->int:return int(state.get("vehicle",0))
func active()->bool:return int(state.get("phase",IDLE))!=IDLE
func seated()->bool:return bool(state.get("seated",false))
func spawn_position()->Vector3:
	return state.driver_position if active() or identity()>0 else host.anchor
func world_active()->bool:
	return game.terrain.world_ready and not game.loading_active and not game.shutdown_requested and not game.terrain.pending_edit and not game.session_menu.pauses_world() and game.app_focused and not game.player_view.entry.active

func capture()->PackedByteArray:
	if is_instance_valid(host.actor) and not seated():
		state.driver_position=host.actor.global_position;state.driver_yaw=host.actor.rotation.y
	state.passenger=game.world_vehicle.passenger==self
	if not store.set_state(state):return PackedByteArray([0])
	return store.capture_storage_snapshot()
func restore(bytes:PackedByteArray)->bool:
	if not store.restore_storage_snapshot(bytes):return false
	_unbind_visuals();state=store.snapshot();restore_passenger=state.passenger;pilot_bound=false;car=null
	if is_instance_valid(host.actor):host.actor.free();host.actor=null;host.human=null
	graph_revision=-1;command.clear();boarding_goal=Vector3.INF
	return true
func changed()->void:
	store.set_state(state);game.terrain.changed_since_save=true

func destinations()->Array:
	var result:Array=[]
	if active():return result
	var plan:Dictionary=game.generated_region.store.get_plan()
	if graph_revision!=game.generated_region.revision():
		graph_revision=game.generated_region.revision();graph_result=planner.configure(plan.get("roads",[]),12 if game.quests.store.snapshot().introduction>0 else 0)
	if not graph_result.get("ok",false):return result
	var start:Vector3=host.anchor
	var heading:=Vector3.ZERO
	if identity()>0:
		var record:Dictionary=game.world_vehicle.fleet.get_record(identity())
		if not record.get("present",false):return result
		start=record.pose.origin;heading=record.pose.basis.z
	var hometown:=-1;var nearest:=INF
	for place:Dictionary in plan.get("places",[]):
		if int(place.id)>=30 and int(place.id)<200 and host.anchor.distance_squared_to(place.position)<nearest:
			nearest=host.anchor.distance_squared_to(place.position);hometown=int(place.id)
	for place:Dictionary in plan.get("places",[]):
		var id:=int(place.id)
		if id<30 or id>=200 or id==hometown:continue
		var outward:Dictionary=planner.route(start,place.position,80,heading)
		if not outward.get("ok",false):continue
		var points:PackedVector3Array=outward.points
		if outward.distance_m<100 or points.size()>8192:continue
		var back:Dictionary=planner.route(points[-1],points[0],1,points[-1]-points[-2])
		if not back.get("ok",false) or points.size()+back.points.size()>8192:continue
		result.append({"id":id,"title":str(place.title),"fare":int(outward.fare),"distance_m":outward.distance_m,"outbound":points,"return_route":back.points,"revision":graph_revision})
	return result

func book(destination:int,revision:int)->Dictionary:
	if active() or not host.reachable() or game.world_vehicle.driving:return {"ok":false,"reason":"The trader is unavailable."}
	if revision!=game.generated_region.revision():return {"ok":false,"reason":"The roads changed. Review the new destinations."}
	var offer:Dictionary={}
	for candidate:Dictionary in destinations():
		if candidate.id==destination:offer=candidate;break
	if offer.is_empty():return {"ok":false,"reason":"No connected road journey and return are available."}
	return _book_offer(offer)

func expedition_offer(location:Dictionary)->Dictionary:
	if active():return {}
	destinations()
	if not graph_result.get("ok",false):return {}
	var start:Vector3=host.anchor
	var heading:=Vector3.ZERO
	if identity()>0:
		var record:Dictionary=game.world_vehicle.fleet.get_record(identity())
		if not record.get("present",false):return {}
		start=record.pose.origin;heading=record.pose.basis.z
	var stop:=Vector3.INF
	for road:Dictionary in game.generated_region.store.get_plan().get("roads",[]):
		if is_equal_approx(float(road.width),4.0) and Vector3(road.b).distance_to(location.marker)<4:
			stop=road.a;break
	if not stop.is_finite():return {}
	var outward:Dictionary=planner.route(start,stop,80,heading)
	if not outward.get("ok",false):return {}
	var points:PackedVector3Array=outward.points
	if points.size()<2 or points[-1].distance_to(stop)>.75:return {}
	var back:Dictionary=planner.route(points[-1],points[0],1,points[-1]-points[-2])
	if not back.get("ok",false) or points.size()+back.points.size()>8192:return {}
	return {"id":0,"title":"Coal mine","fare":0,"outbound":points,"return_route":back.points,"revision":graph_revision}

func book_expedition(offer:Dictionary,key:int)->Dictionary:
	if active() or not host.reachable() or offer.get("revision",-1)!=game.generated_region.revision():return {"ok":false,"reason":"The trader or road is unavailable."}
	return _book_offer(offer,key)

func _book_offer(offer:Dictionary,quest_key:int=0)->Dictionary:
	if Trade.count(game.player_hud.inventory,Trade.CURRENCY)<offer.fare:return {"ok":false,"reason":"You need %d coins for this ride."%offer.fare}
	if not game.world_vehicle.fleet_enabled:return {"ok":false,"reason":"This world has no vehicle fleet."}
	if identity()==0:
		game.world_vehicle.request_scene()
		if not game.world_vehicle.scene_ready():return {"ok":false,"reason":"The trader's car is loading. Try again shortly."}
		var points:PackedVector3Array=offer.outbound;var heading:=Basis(Vector3.UP,atan2(points[1].x-points[0].x,points[1].z-points[0].z))
		var ray:=PhysicsRayQueryParameters3D.create(points[0]+Vector3.UP*3,points[0]-Vector3.UP*3,3,[game.player.get_rid()])
		var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		var placement:Dictionary=preload("res://addons/vehicle_runtime/vehicle_placement.gd").at_ground(game,game.world_vehicle,ground,heading)
		if not placement.ok:return {"ok":false,"reason":"Pickup unavailable: "+placement.reason}
		game.world_vehicle.last_spawn_identity=0
		game.world_vehicle.activation.place(game,placement.pose)
		var id:int=game.world_vehicle.last_spawn_identity
		if id==0:return {"ok":false,"reason":"The trader's car cannot be placed here."}
		state.vehicle=id
		state.driver_position=host.actor.global_position;state.driver_yaw=host.actor.rotation.y
	var gifted_slot:=-1
	if quest_key>0:
		var quest:Dictionary=game.quests.store.snapshot()
		if quest.introduction==2:
			var before:Dictionary=game.player_hud.inventory.snapshot()
			var accepted:Dictionary=game.quests.store.accept_first_visit(quest_key,game.player_hud.inventory,quest.revision,game.player_hud.inventory.snapshot().revision)
			if not accepted.ok:changed();return {"ok":false,"reason":"Make room in your backpack for the torch, rifle and ammunition. No supplies were taken or duplicated."}
			var received:Dictionary=game.player_hud.inventory.snapshot()
			for slot in received.slots.size():
				if received.slots[slot].item==8 and before.slots[slot].item!=8:gifted_slot=slot;break
		elif quest.introduction!=3 or quest.key!=quest_key:return {"ok":false,"reason":"The expedition changed. Review your quest."}
		game.player_hud.refresh()
	state.expedition=quest_key>0
	state.phase=BOARDING;state.fare=offer.fare;state.destination=offer.id;state.title=offer.title
	state.outbound=offer.outbound;state.return_route=offer.return_route;state.cursor=0;state.paid=false;state.passenger=false;state.seated=false
	state.home=host.anchor;state.driver_position=host.actor.global_position;state.driver_yaw=host.actor.rotation.y
	boarding_goal=Vector3.INF;pilot_bound=false;changed();host.ui.close()
	# Closing the trader restores HUD input; use ordinary belt move/swap rules.
	if gifted_slot>=0:game.player_hud.equip_inventory(gifted_slot)
	status_text="Coal-mine expedition · supplies received · free return ride\nFollow the trader to the car." if state.expedition else "Ride reserved to %s · %d coins when you board\nFollow the trader to the car. Hold E by the car to cancel."%[state.title,state.fare]
	return {"ok":true,"reason":status_text}

func board()->bool:
	if not active():game._show_lake_notice("Choose a destination at the trader's shop first.");return false
	if state.phase==HOME_WALK or (state.phase==RETURNING and not state.expedition):game._show_lake_notice("The trader is returning home.");return false
	if not world_active():return false
	if not state.seated or not is_instance_valid(car):
		game._show_lake_notice("The trader is still walking to the car.");return false
	if not state.paid:
		_probe(true)
		if not probe_ready or not probe_clear:
			game._show_lake_notice("The departure road is still loading." if not probe_ready else "Clear the road ahead before boarding. No coins charged.");return false
		var fare:=PackedInt64Array([Trade.CURRENCY,state.fare])
		if not state.expedition and (not game.player_hud.inventory.can_afford(fare,game.player_hud.inventory.snapshot().revision).ok or not host.trader.stock.can_receive(fare,host.trader.stock.snapshot().revision).ok):
			game._show_lake_notice("Payment unavailable. Check your coins and the trader's purse.");return false
	if not game.world_vehicle.enter_passenger(game,identity(),self):return false
	if not state.paid and not state.expedition:
		var inventory:RefCounted=game.player_hud.inventory
		var paid:Dictionary=inventory.transfer_items_to(host.trader.stock,PackedInt64Array([Trade.CURRENCY,state.fare]),inventory.snapshot().revision,host.trader.stock.snapshot().revision)
		if not paid.ok:
			game.world_vehicle.exit_passenger(game,self);game._show_lake_notice("Payment failed. Check your coins and the trader's purse.");return false
		host.trader.saved_stock.flush_pending();state.paid=true
	if state.expedition:state.paid=true
	var restoring:=restore_passenger
	state.passenger=true;restore_passenger=false
	if state.phase==BOARDING:state.phase=OUTBOUND;state.cursor=0;pilot_bound=false
	elif state.expedition and not restoring and state.phase==ARRIVED:state.phase=RETURNING;state.cursor=0;pilot_bound=false;command.clear()
	elif state.expedition and not restoring and state.phase in [STOPPING,RETURN_STOPPED]:state.phase=RETURNING if state.phase==RETURN_STOPPED else OUTBOUND;pilot_bound=false;command.clear()
	_make_passenger_view();changed();game.player_hud.refresh();return true

func cancel_reservation()->String:
	if state.phase!=BOARDING:return "This car belongs to the trader."
	if is_instance_valid(car) and state.seated:
		if not _driver_exit():return "The trader needs a clear exit beside the car."
	state.phase=HOME_WALK;state.seated=false;state.passenger=false;state.cursor=0;changed()
	return "Ride cancelled. No coins were charged."

func abandon_for_respawn()->void:
	state.passenger=false;restore_passenger=false;_remove_passenger_view()
	if state.phase==OUTBOUND:state.phase=STOPPING
	elif state.phase==RETURNING:state.phase=RETURN_STOPPED
	command.clear();changed()

func request_exit()->String:
	if game.world_vehicle.passenger!=self:return ""
	if state.expedition:return _expedition_exit()
	if state.phase==OUTBOUND:
		state.phase=STOPPING;changed();return "The trader is stopping. Press E again when stopped to cancel and get your fare back."
	if car.linear_velocity.length()>.25:return "Wait for the car to stop."
	if not game.world_vehicle.safe_exit_for(game,car,game.player.get_rid()).is_finite():return "No clear, loaded exit beside the car."
	var cancelled:bool=state.phase!=ARRIVED
	var message:String=game.world_vehicle.exit_passenger(game,self)
	if game.world_vehicle.passenger==self:return message
	state.passenger=false;_remove_passenger_view()
	if cancelled:
		state.refund=int(state.refund)+int(state.fare);state.paid=false;_refund()
		# Finish the already validated forward road itinerary before returning.
		# A blocked road stays blocked; cancellation never flips or teleports a car.
		var remainder:PackedVector3Array=state.outbound.slice(int(state.cursor))
		var returning:PackedVector3Array=remainder
		returning.append_array(state.return_route.slice(1));state.return_route=returning
	state.phase=RETURNING;state.cursor=0;pilot_bound=false;command.clear();changed()
	status_text="The trader is returning home."
	if cancelled:return "Ride cancelled; fare refunded." if state.refund==0 else "Ride cancelled; make room in your backpack to receive the fare refund."
	return "You have arrived. The trader is driving home."

func _expedition_exit()->String:
	if state.phase in [OUTBOUND,RETURNING]:
		state.phase=STOPPING if state.phase==OUTBOUND else RETURN_STOPPED;changed();return "Stopping safely. Press E again once stopped."
	if car.linear_velocity.length()>.25:return "Wait for the car to stop."
	var message:String=game.world_vehicle.exit_passenger(game,self)
	if game.world_vehicle.passenger==self:return message
	state.passenger=false;_remove_passenger_view()
	if state.phase==HOME_ARRIVED:
		if _driver_exit():state.phase=HOME_WALK;state.cursor=0;pilot_bound=false;command.clear()
	changed()
	return "Home again. Talk to the trader about your quest." if state.phase in [HOME_WALK,HOME_ARRIVED] else "The trader is waiting here. Press E by the car to return or continue."

func _refund()->void:
	if int(state.refund)<=0:return
	var inventory:RefCounted=game.player_hud.inventory
	var result:Dictionary=host.trader.stock.transfer_items_to(inventory,PackedInt64Array([Trade.CURRENCY,state.refund]),host.trader.stock.snapshot().revision,inventory.snapshot().revision)
	if result.ok:state.refund=0;host.trader.saved_stock.flush_pending();game.player_hud.refresh();changed()

func _physics_process(delta:float)->void:
	if state.is_empty():return
	next_service-=delta
	if next_service<=0:
		next_service=.2
		if world_active():_refund()
		if active():
			_update_interest();_admit_car()
			if state.phase in [BOARDING,HOME_WALK]:_shop_door_access()
	if not active():
		if is_instance_valid(label):label.visible=false
		if not _last_interest.is_empty():_interest(PackedVector3Array())
		return
	if not world_active():
		if is_instance_valid(car):
			car.streaming.discard_motion(car);car.freeze=true;car.set_physics_process(false)
		return
	if not is_instance_valid(car):status_text="Trader ride · waiting for the car's road and collision to load";_present();return
	car.streaming.owns_focus=game.world_vehicle.passenger==self
	if restore_passenger and game.world_vehicle.passenger!=self and game.world_vehicle.can_interact():
		if not board():status_text="Saved ride · approach the trader's car and press E to resume without another fare."
	if state.phase in [BOARDING,HOME_WALK]:_walk(delta)
	if state.phase in [OUTBOUND,RETURNING,ARRIVED,STOPPING,HOME_ARRIVED,RETURN_STOPPED]:
		if not pilot_bound and state.phase in [OUTBOUND,RETURNING]:
			_restore_return_approach()
			pilot_bound=pilot.resume(state.return_route if state.phase==RETURNING else state.outbound,int(state.cursor))
			if not pilot_bound:status_text="Trader ride · saved road route is unavailable";return
			command.clear()
		if state.phase in [OUTBOUND,RETURNING] and ((state.phase==RETURNING and not state.expedition) or game.world_vehicle.passenger==self):
			car.autonomous_controls=_controls;car.set_controls_enabled(false);car.set_physics_process(true)
			if car.freeze and not car.streaming.waiting:car.freeze=false
		if command.get("state","")=="arrived" and state.phase in [OUTBOUND,RETURNING]:
			if state.phase==OUTBOUND:
				state.phase=ARRIVED;changed()
			elif state.expedition and state.passenger:
				state.phase=HOME_ARRIVED;changed()
			elif _driver_exit():
				state.phase=HOME_WALK;state.cursor=0;pilot_bound=false;command.clear();changed()
	# Service brakes can creep on a slope while the expedition waits. Once the
	# real chassis has stopped, park it until boarding enables the motor again.
	if state.phase in [ARRIVED,STOPPING,HOME_ARRIVED,RETURN_STOPPED] and car.linear_velocity.length()<.25:
		car.streaming.discard_motion(car);car.freeze=true;car.set_physics_process(false)
	if state.phase==HOME_ARRIVED and not state.passenger and _driver_exit():state.phase=HOME_WALK;state.cursor=0;pilot_bound=false;command.clear();changed()
	if state.expedition and state.phase==ARRIVED:status_text=("Coal mine · E to get out" if state.passenger else "Trader waiting · board the car to return")+"\nI'll wait here. Board again to go home, whether or not the quest is finished."
	elif state.phase==HOME_ARRIVED:status_text="Home again · E to get out"
	elif state.expedition and state.phase in [STOPPING,RETURN_STOPPED]:status_text="Stopping safely…" if car.linear_velocity.length()>.25 else "Stopped · E to get out. Board again to continue."
	elif state.phase==ARRIVED:status_text="Arrived at %s · E to get out\nThe trader will drive home after you leave."%state.title
	elif state.phase==STOPPING:status_text="Stopping safely…" if car.linear_velocity.length()>.25 else "Stopped · E to cancel, get out and receive your fare refund."
	_update_seated_actor();_present()

func _restore_return_approach()->void:
	# A stopped car can roll downhill while the passenger is away. The native
	# follower measures distance to its first endpoint, so a car behind that
	# endpoint must retain the already driven approach rather than invent a link.
	if state.phase!=RETURNING or int(state.cursor)!=0 or not is_instance_valid(car):return
	var outward:PackedVector3Array=state.outbound
	var returning:PackedVector3Array=state.return_route
	if outward.size()<2 or returning.size()<2 or outward.size()+returning.size()>8192:return
	if outward[-1].distance_to(returning[0])>.05:return
	var position:Vector3=car.global_position
	if position.distance_to(returning[0])>12:return
	var forward:Vector3=car.global_basis.z;forward.y=0
	var best:=-1;var nearest:=1.0
	for index in range(maxi(0,outward.size()-33),outward.size()-1):
		var direction:Vector3=outward[index+1]-outward[index];direction.y=0
		if direction.length_squared()<.001 or direction.normalized().dot(forward.normalized())<.8:continue
		var offset:Vector3=position-outward[index];offset.y=0
		var fraction:float=offset.dot(direction)/direction.length_squared()
		if fraction<0 or fraction>1:continue
		var projected:Vector3=outward[index].lerp(outward[index+1],fraction)
		var lateral:Vector3=position-projected;lateral.y=0
		if absf(position.y-projected.y)>3 or lateral.length_squared()>=nearest:continue
		nearest=lateral.length_squared();best=index
	if best<0:return
	var restored:PackedVector3Array=outward.slice(best)
	restored.append_array(returning.slice(1))
	if outward.size()+restored.size()>8192:return
	state.return_route=restored;changed()

func _controls(delta:float)->Dictionary:
	if not world_active() or state.phase in [ARRIVED,STOPPING,BOARDING,HOME_WALK,HOME_ARRIVED,RETURN_STOPPED] or ((state.phase==OUTBOUND or state.expedition) and game.world_vehicle.passenger!=self):return {"hold":true}
	probe_remaining-=delta
	if probe_remaining<=0:probe_remaining=.1;_probe()
	command=pilot.advance(car.global_transform,car.linear_velocity,delta,probe_ready,probe_clear)
	state.cursor=command.cursor
	if command.state=="following":status_text=("Returning home" if state.phase==RETURNING else "Riding to "+state.title)+" · %.0f km/h"%(car.linear_velocity.length()*3.6)+(("\nE · Ask to stop" if state.expedition else "\nE · Ask to stop and cancel") if state.passenger else "")
	elif command.state in ["blocked","unavailable"]:status_text="Trader ride · "+("road obstructed" if command.state=="blocked" else "waiting for road collision")+"\n"+(("E · Ask to stop" if state.expedition else "E · Stop, cancel and get your fare back") if state.passenger else "The trader will continue when the road is clear.")
	if command.state=="blocked":
		next_retry-=delta
		if next_retry<=0:next_retry=2;pilot.resume(state.return_route if state.phase==RETURNING else state.outbound,int(state.cursor))
	return command

func _probe(boarding:bool=false)->void:
	var speed:float=car.linear_velocity.length();var distance:=clampf(1.5+speed*speed/16,1.5,6)
	var forward:Vector3=car.global_basis.z
	var bounds:=AABB(car.position-Vector3(3.5,2,3.5),Vector3(7,5,7)).expand(car.position+forward*(distance+3)).grow(.5)
	probe_ready=game._actor_collision_ready(bounds);probe_clear=false;probe_reason="collision publication"
	# Global tree and boulder owners must have reconciled current terrain before
	# a missing proxy can mean empty space. At most four owners of either grid.
	for z in range(floori(bounds.position.z/64),floori(bounds.end.z/64)+1):
		for x in range(floori(bounds.position.x/64),floori(bounds.end.x/64)+1):
			var key:=Vector2i(x,z)
			if not game.ecosystem.resident.has(key) or game.ecosystem._resample.has(key) or game.ecosystem._reconcile.has(key) or game.ecosystem._pending_cells.has(key):probe_ready=false
	if game.ground_enabled and game.ground_cover.boulders!=null:
		var boulders:Node=game.ground_cover.boulders
		for z in range(floori(bounds.position.z/64),floori(bounds.end.z/64)+1):
			for x in range(floori(bounds.position.x/64),floori(bounds.end.x/64)+1):
				var key:=Vector2i(x,z)
				# Empty published owners legitimately have no resident rock rows.
				if not boulders._published.has(key) or boulders._pending.has(key) or boulders._resample.has(key) or boulders._reconcile.has(key):probe_ready=false
	if not probe_ready:return
	var road_samples:Array=[]
	for x:float in [-1.0,0.0,1.0]:
		for z:float in [-1.9,0.0,1.9]:road_samples.append(Transform3D(Basis.IDENTITY,car.global_transform*Vector3(x,0,z)))
	var road_mask:PackedByteArray=game.generated_region.store.placement_mask(road_samples,0)
	probe_reason="road footprint"
	if road_mask.size()!=9 or road_mask.has(0):return
	_probe_query.transform=car.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,.34,-.02));_probe_query.motion=forward*distance
	var excluded:Array[RID]=[car.get_rid()]
	if boarding:excluded.append(game.player.get_rid())
	_probe_query.exclude=excluded
	var space:PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	probe_reason="chassis obstruction"
	if not space.intersect_shape(_probe_query,1).is_empty():return
	var motion:PackedFloat32Array=space.cast_motion(_probe_query)
	probe_reason="braking sweep"
	if motion.size()!=2 or motion[0]<.999:return
	# Four supported wheel approaches; collision guard remains authoritative after
	# road edits. No collision disabling, pose correction or straight-line fallback.
	for side:float in [-.85,.85]:
		for ahead:float in [0.0,minf(distance,2.0)]:
			var at:Vector3=car.position+car.global_basis.x*side+forward*(1.4+ahead)
			var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2,3,excluded))
			probe_reason="wheel support"
			if hit.is_empty() or hit.normal.y<.7:return
	probe_clear=true;probe_reason=""

func _admit_car()->void:
	var session:Node=game.world_vehicle
	if not session.fleet_enabled or identity()==0:return
	if not session.fleet.get_record(identity()).get("present",false):status_text="Trader ride · vehicle record unavailable";return
	if not session.activation.residents.has(identity()):session.activation.admit(game,identity())
	car=session.activation.residents.get(identity())
	if not is_instance_valid(car):return
	car.autonomous_controls=_controls;car.set_controls_enabled(false)
	if state.seated and not is_instance_valid(driver_view):driver_view=Seat.create(car,[{"item":301,"count":1},{"item":302,"count":1},{"item":303,"count":1}],true)
	car.streaming.owns_focus=session.passenger==self

func _walk(delta:float)->void:
	if not is_instance_valid(host.actor):return
	var actor:CharacterBody3D=host.actor
	door_retry=maxf(0,door_retry-delta)
	if state.phase==BOARDING and state.seated:
		status_text="Coal-mine expedition · E by the car to board\nFree return ride. I'll wait at the mine." if state.expedition else "Ready for %s · %d coins · E by the car to board\nHold E and choose Cancel reservation to cancel free."%[state.title,state.fare];return
	if state.phase==BOARDING and not boarding_goal.is_finite():boarding_goal=game.world_vehicle.safe_exit_for(game,car,actor.get_rid())
	var goal:Vector3=state.home if state.phase==HOME_WALK else boarding_goal
	if not goal.is_finite():status_text="Trader ride · waiting for a safe boarding place";return
	navigator.set_agent(1,actor.global_position,goal,0,true)
	navigator.advance(delta,game._actor_collision_ready,Callable())
	walk_status=navigator.state(1)
	var target:Vector3=navigator.steering_target(1);var movement:=Vector3.ZERO
	if walk_status=="following" and target.is_finite():
		_open_route_door(actor,target)
		movement=target-actor.global_position;movement.y=0
		if movement.length()>.03:movement=movement.normalized()*2.1
		if not navigator.guard_motion(1,movement,movement.length()*delta):movement=Vector3.ZERO
	if not game._actor_collision_ready(AABB(actor.position-Vector3(.5,.1,.5),Vector3(1,2,1))):return
	actor.velocity=Vector3(movement.x,0 if actor.is_on_floor() else actor.velocity.y-20*delta,movement.z)
	motor.move_grounded(actor,delta)
	if movement.length_squared()>.01:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(movement.x,movement.z),minf(1,delta*8))
	host.animate_walk(movement.length_squared()>.01)
	state.driver_position=actor.global_position;state.driver_yaw=actor.rotation.y
	status_text=("Trader walking home" if state.phase==HOME_WALK else "Follow the trader to the car · free expedition" if state.expedition else "Follow the trader to the car · no coins charged yet")+(" · "+walk_status if walk_status in ["blocked","unavailable","search_limit"] else "")
	if actor.global_position.distance_to(goal)<.65 and walk_status=="arrived":
		if state.phase==HOME_WALK:
			state.phase=IDLE;state.paid=false;state.seated=false;state.passenger=false;state.cursor=0;state.outbound=PackedVector3Array();state.return_route=PackedVector3Array()
			car.autonomous_controls=Callable();car.set_controls_enabled(false);car.freeze=true;car.set_physics_process(false);car.streaming.owns_focus=false
			game.world_vehicle.sync_body(identity(),car);_interest(PackedVector3Array());host.animate_walk(false)
		else:
			state.seated=true;actor.collision_layer=0;actor.collision_mask=0;actor.hide()
			driver_view=Seat.create(car,[{"item":301,"count":1},{"item":302,"count":1},{"item":303,"count":1}],true)
		changed()

func _open_route_door(actor:CharacterBody3D,target:Vector3)->void:
	if door_retry>0:return
	door_retry=.25
	# Door permission is not a request to open every nearby leaf. Approach a
	# visible door only when it is ahead of both the native steering direction
	# and the walk's goal. Open early enough to stand outside the swing envelope.
	var origin:Vector3=actor.global_position+Vector3.UP*.9
	var heading:Vector3=target-actor.global_position;heading.y=0
	var goal:Vector3=(state.home if state.phase==HOME_WALK else boarding_goal)-actor.global_position;goal.y=0
	if heading.length_squared()<.0001 or goal.length_squared()<.0001:return
	for door:Dictionary in shop_doors:
		if door.entry.state.is_open(door.id) or door.entry.state.is_moving(door.id):continue
		var values:PackedFloat32Array=door.entry.collection.get_instance(door.id)
		if values.size()!=12:continue
		var center:Vector3=door.position+Vector3(values[0],values[4],values[8])*.5
		var offset:Vector3=center-actor.global_position;offset.y=0
		if offset.length_squared()>9 or offset.dot(goal)<=0 or offset.normalized().dot(heading.normalized())<.5:continue
		var query:=PhysicsRayQueryParameters3D.create(origin,center+Vector3.UP*.9,15,[actor.get_rid()])
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.rid!=door.entry.collection.collision_body_for(door.id):continue
		var opened:Dictionary=door.entry.state.animate_toggle(door.entry.collection,door.id,AABB())
		if opened.ok:game.terrain.changed_since_save=true
		door_retry=1;return

func _shop_door_access()->void:
	# Explicit trader permission is limited to the original shop footprint.
	# Native planning may propose these leaves; motion still waits for the
	# ordinary animated swing and its actor/vehicle obstruction checks.
	var prefab:Resource=preload("res://addons/structures/civic_catalog.gd").asset(0)
	var local_anchor:Transform3D=prefab.get_meta("trader_anchor")
	var bounds:AABB=prefab.placement_bounds(Vector3i.ZERO,0)
	bounds.position+=state.home-local_anchor.origin
	var doors:Array[RID]=[];shop_doors.clear()
	for entry:Dictionary in game.doors.types.values():
		for id:int in entry.collection.collision_identities():
			if shop_doors.size()>=16:break
			var values:PackedFloat32Array=entry.collection.get_instance(id)
			if values.size()!=12:continue
			var position:Vector3=entry.collection.to_global(Vector3(values[3],values[7],values[11]))
			if not bounds.grow(.5).has_point(position):continue
			shop_doors.append({"entry":entry,"id":id,"position":position})
			var rid:RID=entry.collection.collision_body_for(id)
			if rid.is_valid() and not entry.state.is_open(id):doors.append(rid)
	navigator.set_interactions(doors)

func _driver_exit()->bool:
	if not is_instance_valid(host.actor) or car.linear_velocity.length()>.25:return false
	var feet:Vector3=game.world_vehicle.safe_exit_for(game,car,host.actor.get_rid())
	if not feet.is_finite():return false
	car.autonomous_controls=Callable();car.set_controls_enabled(false);car.freeze=true;car.set_physics_process(false)
	state.seated=false;state.driver_position=feet;host.actor.global_position=feet;host.actor.velocity=Vector3.ZERO
	host.actor.collision_layer=8;host.actor.collision_mask=15|(1<<16)|(1<<18);host.actor.show()
	if is_instance_valid(driver_view):driver_view.queue_free();driver_view=null
	navigator.clear();navigator.set_exclusions([host.actor.get_rid()]);return true

func actor_created()->void:
	navigator.clear();navigator.set_exclusions([host.actor.get_rid()])
	host.actor.rotation.y=float(state.driver_yaw)
	if seated():host.actor.collision_layer=0;host.actor.collision_mask=0;host.actor.hide()
func _update_seated_actor()->void:
	if seated() and is_instance_valid(host.actor):host.actor.global_position=car.global_position;state.driver_position=car.global_position
func _make_passenger_view()->void:
	if not is_instance_valid(passenger_view):passenger_view=Seat.create(car,game.player_hud.equipment.snapshot(1).slots,false)
func _remove_passenger_view()->void:
	if is_instance_valid(passenger_view):passenger_view.queue_free();passenger_view=null
func _unbind_visuals()->void:
	_remove_passenger_view()
	if is_instance_valid(driver_view):driver_view.queue_free();driver_view=null
	if is_instance_valid(car):car.autonomous_controls=Callable();car.set_controls_enabled(false)
func _update_interest()->void:
	var record:Dictionary=game.world_vehicle.fleet.get_record(identity())
	if not record.get("present",false):return
	var point:Vector3=car.global_position if is_instance_valid(car) else record.pose.origin
	var direction:Vector3=car.global_basis.z if is_instance_valid(car) else record.pose.basis.z
	var points:=PackedVector3Array([point])
	if state.phase in [BOARDING,HOME_WALK]:
		points.append(state.driver_position)
		var frontier:PackedVector3Array=navigator.interest_points()
		points.append(frontier[-1] if not frontier.is_empty() else state.home)
	else:points.append(point+direction*12)
	_interest(points)
func _interest(points:PackedVector3Array)->void:
	for index in points.size():points[index]=points[index].snapped(Vector3(4,1,4))
	if points==_last_interest:return
	_last_interest=points;game.navigation_residency.set_service(points)
func _present()->void:
	label.visible=active() and (state.passenger or game.player.global_position.distance_to(state.driver_position)<(8 if state.expedition and state.phase==ARRIVED else 100))
	label.text=status_text+("\nRefund waiting: make room for %d coins."%state.refund if state.refund>0 else "")
func _exit_tree()->void:
	_unbind_visuals()
	if is_instance_valid(game):game.navigation_residency.set_service(PackedVector3Array())
