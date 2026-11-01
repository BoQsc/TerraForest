# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
var stage:="full"
var samples:Array=[]
var frame_ms:Array[float]=[]
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--ride-stage="):stage=argument.trim_prefix("--ride-stage=")
	super._initialize()
func run()->void:
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(receipt.slot).begins_with("TraderRide_"),"only this test's private generated-world copy opens"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	if not check(await open_world(receipt.slot,false,1,1703,true),"generated world opens through normal browser lifecycle"):await finish();return
	var game:=current_scene;game.background_fps=30;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	if not check(await wait_for(func():return not game.player_view.entry.active,15),"entry camera finishes before player actions"):await finish();return
	var ride:Node=game.trader.ride
	check(ProjectSettings.get_setting("terraforest/offscreen_session",false) and not preload("res://addons/world_runtime/mouse_ownership.gd").set_mode(game,Input.MOUSE_MODE_CAPTURED),"offscreen policy rejects an explicit capture request")
	# Headless input ownership substitute only: retain all interaction gates
	# except pointer capture, so this offscreen check never steals user input.
	game.world_vehicle.interaction_available=func():return not game.player_view.entry.active and not game.loading_active and not game.shutdown_requested and game.app_focused and game.terrain.world_ready and not game.terrain.pending_edit and not game.player_hud.inventory_open
	if stage=="return-resume":
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json")))
		if not check(ride.state.phase==ride.RETURNING and ride.identity()==int(expected.vehicle) and not ride.state.passenger,"fresh process restores the same unoccupied return after cancellation"):await finish();return
		if not check(await wait_for(func():return is_instance_valid(ride.car),20),"returning vehicle admits independently of the player"):await finish();return
		var origin:Vector3=ride.car.position;var player_origin:Vector3=game.player.position
		check(await watch(func():return ride.car.position.distance_to(origin)>20,30),"saved unoccupied return resumes real road travel")
		check(game.world_vehicle.passenger==null and not game.world_vehicle.driving and game.player.position.distance_to(player_origin)<.1,"return reload leaves the player on foot")
		check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==int(expected.coins) and ride.state.refund==0,"refund stays exact after return reload")
		await finish();return
	if stage=="complete":
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json")))
		if not check(ride.state.paid and ride.identity()==int(expected.vehicle) and Trade.count(game.player_hud.inventory,Trade.CURRENCY)==int(expected.coins),"fresh process restores the paid journey, car identity and exact wallet"):await finish();return
		if not check(await watch(func():return game.world_vehicle.passenger==ride,25),"saved passenger reboards the same moving service without another purchase"):await finish();return
		check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==int(expected.coins),"automatic reboarding does not charge twice")
		await seat_photograph(game,ride)
		await complete_journey(game,ride,ride.state.outbound[-1],int(expected.coins),ride.identity(),ride.state.home)
		return
	if stage=="resume":
		check(ride.active(),"saved journey restores in a fresh process")
		check(await wait_for(func():return is_instance_valid(ride.car),20),"saved service car admits")
		board_diagnostic(game,ride)
		if ride.state.phase==ride.BOARDING:
			check(game.world_vehicle.enter(game,ride.identity()),"saved boarding reservation enters without another car")
		else:check(await wait_for(func():return game.world_vehicle.passenger==ride,20),"saved passenger reboards without another charge")
		await finish();return
	var point:=Vector3.INF
	for place:Dictionary in game.generated_region.store.get_plan().get("places",[]):
		if place.id==game.trader.PLACE:point=place.position;break
	if not check(point.is_finite(),"published plan contains the resident trader"):await finish();return
	# Fixture setup only. Every service, boarding, ride and return movement below
	# uses the production bodies and motors without changing their transforms.
	game.teleport(point+Vector3(0,0,1.6))
	if not check(await wait_for(func():return not game.loading_active and is_instance_valid(game.trader.actor),90),"real loaded shop admits the trader"):await finish();return
	var reachable:=false
	for offset in [Vector3(0,0,1.6),Vector3(0,0,-1.6),Vector3(1.6,0,0),Vector3(-1.6,0,0)]:
		game.player.global_position=point+offset;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(point+Vector3.UP*1.45)
		for i in 5:await physics_frame
		game.app_focused=true
		if game.trader.reachable():reachable=true;break
	if not check(reachable,"ordinary scene ray reaches the shopkeeper"):await finish();return
	game.world_vehicle.request_scene()
	check(await wait_for(func():return game.world_vehicle.scene_ready(),20),"service car asset available")
	var offers:Array=ride.destinations();offers.sort_custom(func(a:Dictionary,b:Dictionary):return a.distance_m<b.distance_m)
	var plan:Dictionary=game.generated_region.store.get_plan()
	FileAccess.open(folder.path_join("plan.json"),FileAccess.WRITE).store_string(JSON.stringify(plan,"  "))
	print("RIDE_OFFERS count=",offers.size()," anchor=",point," graph=",ride.graph_result)
	for place:Dictionary in plan.places:
		if int(place.id)<30 or int(place.id)>=200:continue
		var outward:Dictionary=ride.planner.route(point,place.position,80)
		var back:Dictionary={}
		if outward.get("ok",false):back=ride.planner.route(outward.points[-1],outward.points[0],1,outward.points[-1]-outward.points[-2])
		print("TOWN_ROUTE id=",place.id," title=",place.title," point=",place.position," outward=",outward.get("reason",outward.get("distance_m",0))," back=",back.get("reason",back.get("distance_m",0)))
	FileAccess.open(folder.path_join("offers.json"),FileAccess.WRITE).store_string(JSON.stringify(offers,"  "))
	if not check(not offers.is_empty(),"published roads offer a complete town trip and forward return"):await finish();return
	game.player_hud.inventory.grant_items(PackedInt64Array([Trade.CURRENCY,10000]),game.player_hud.inventory.snapshot().revision)
	check(game.trader.try_open({"collider":game.trader.actor}),"normal interaction opens travel and trade choices")
	await photograph("destination-menu")
	if stage=="inspect":await finish();return
	var offer:Dictionary=offers[0]
	var before:=Trade.count(game.player_hud.inventory,Trade.CURRENCY)
	for i in game.trader.ui.towns.item_count:
		if game.trader.ui.towns.get_item_metadata(i).id==offer.id:game.trader.ui.towns.select(i)
	game.trader.ui.reserve.pressed.emit()
	if not check(ride.state.phase==ride.BOARDING and not game.trader.ui.opened,"reserve button creates one service and closes the shop"):print("BOOK_NOTICE ",game.trader.ui.notice.text);await finish();return
	check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==before,"reservation does not charge before boarding")
	var identity:int=ride.identity()
	if not check(await watch(func():return ride.state.seated,120),"trader physically walks from counter to car"):await photograph("boarding-failure");await finish();return
	await photograph("driver-boarded")
	if not check(await walk_player_to_car(game,ride),"player physically walks to the parked service car"):await photograph("player-walk-failure");await finish();return
	var obstruction:=StaticBody3D.new();var obstacle_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,1);obstacle_shape.shape=box;obstruction.add_child(obstacle_shape);game.add_child(obstruction)
	obstruction.global_position=ride.car.global_transform*Vector3(0,.8,2.6)
	for tick in 3:await physics_frame
	check(not game.world_vehicle.enter(game,identity) and not ride.state.paid and Trade.count(game.player_hud.inventory,Trade.CURRENCY)==before,"physical departure obstruction rejects boarding without charging")
	obstruction.free()
	for tick in 3:await physics_frame
	if not check(game.world_vehicle.enter(game,identity),"ordinary car interaction boards as passenger"):
		print("BOARD_DIAGNOSTIC ",{"active":ride.world_active(),"can_interact":game.world_vehicle.can_interact(),"reachable":game.world_vehicle.reachable(game,identity),"phase":ride.state.phase,"seated":ride.state.seated,"driving":game.world_vehicle.driving,"car_id":game.world_vehicle.car_identity,"parked":game.world_vehicle.activation.parked_status,"ready":ride.probe_ready,"clear":ride.probe_clear,"reason":ride.probe_reason})
		await finish();return
	check(game.world_vehicle.passenger==ride and ride.state.paid and Trade.count(game.player_hud.inventory,Trade.CURRENCY)==before-offer.fare,"one atomic payment seats the passenger")
	check(await wait_for(func():return game._vehicle_ui_active and game.help.text.begins_with("Trader ride"),3) and not game._walking_help.begins_with("Trader ride"),"passenger help keeps the ordinary walking instructions for exit")
	for tick in 2:await physics_frame
	check(is_instance_valid(ride.driver_view) and is_instance_valid(ride.passenger_view),"both existing humanoids have visible seat representations")
	await seat_photograph(game,ride)
	var departed:Vector3=ride.car.position
	if not check(await watch(func():return ride.car.position.distance_to(departed)>30,40),"native driver departs under real wheel and chassis physics"):await photograph("departure-failure");await finish();return
	# Freeze the world using the actual pause policy while capturing a compound
	# snapshot; this also checks that an occupied paid route validates for F5.
	game.session_menu.set_open(true)
	var saved:PackedByteArray=ride.capture()
	check(saved.size()>96 and ride.store.validate_snapshot(saved),"mid-ride paid route is archive-valid")
	var paused:Vector3=ride.car.position
	for tick in 30:await physics_frame
	check(ride.car.position.distance_to(paused)<.1,"pause holds the occupied car")
	game.session_menu.set_open(false);game.app_focused=true
	if stage=="cancel":
		check(game.world_vehicle.exit_vehicle(game).contains("stopping") and ride.state.phase==ride.STOPPING and game.world_vehicle.passenger==ride,"early exit requests a physical stop before releasing the passenger")
		if not check(await watch(func():return ride.car.linear_velocity.length()<.25,20),"cancellation brakes the actual car to a stop"):await finish();return
		check(await wait_for(func():return ride.status_text.begins_with("Stopped"),3),"stopped cancellation presents the safe exit and refund action")
		var exit_message:String=game.world_vehicle.exit_vehicle(game)
		check(game.world_vehicle.passenger==null and ride.state.phase==ride.RETURNING,"safe cancellation exit starts the forward return: "+exit_message)
		check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==before and ride.state.refund==0 and not ride.state.paid,"cancelled journey refunds exactly the original fare")
		var refund_bytes:PackedByteArray=ride.capture()
		check(ride.store.validate_snapshot(refund_bytes),"cancelled forward return and cleared refund remain saveable")
		FileAccess.open(folder.path_join("expected.json"),FileAccess.WRITE).store_string(JSON.stringify({"vehicle":identity,"coins":before,"fare":offer.fare},"  "))
		await photograph("cancelled-refunded");await finish();return
	if stage=="depart":
		FileAccess.open(folder.path_join("expected.json"),FileAccess.WRITE).store_string(JSON.stringify({"vehicle":identity,"coins":before-offer.fare,"fare":offer.fare},"  "))
		await finish();return
	await complete_journey(game,ride,offer.outbound[-1],before-offer.fare,identity,point)
func complete_journey(game:Node,ride:Node,stop:Vector3,coins:int,identity:int,home:Vector3)->void:
	if not check(await watch(func():return ride.state.phase==ride.ARRIVED,360),"car follows the published roads and stops at the selected town"):await photograph("outbound-failure");await finish();return
	check(ride.car.linear_velocity.length()<.25 and ride.car.position.distance_to(stop)<3,"arrival is stopped at the quoted road stop")
	await photograph("destination-arrival")
	var message:String=game.world_vehicle.exit_vehicle(game)
	if not check(game.world_vehicle.passenger==null and not game.world_vehicle.driving and ride.state.phase==ride.RETURNING,"getting out starts the trader's unoccupied return: "+message):await finish();return
	var player_at:Vector3=game.player.position
	check(Trade.count(game.player_hud.inventory,Trade.CURRENCY)==coins,"completed fare remains paid exactly once")
	await photograph("trader-leaving")
	if not check(await watch(func():return not ride.active(),420),"trader drives home while player stays in the destination town, then walks to the counter"):await photograph("return-failure");await finish();return
	check(game.player.position.distance_to(player_at)<.1 and game.terrain.focus.distance_to(player_at)<5,"remote return preserves the player's position and streaming focus")
	check(ride.identity()==identity and not ride.state.seated and ride.state.driver_position.distance_to(home)<.8,"same persistent trader and reserved car reach home, with the distant pedestrian eligible for normal culling")
	check(not game.world_vehicle.remove_vehicle(identity),"service car cannot be picked up or deleted through player vehicle action")
	check(not ride.destinations().is_empty(),"returned trader can quote another town without duplicating the car")
	await finish()
func seat_photograph(game:Node,ride:Node)->void:
	game.app_focused=false
	var camera:=Camera3D.new();game.add_child(camera)
	camera.global_position=ride.car.global_transform*Vector3(3,1.8,3.3)
	camera.look_at(ride.car.global_position+Vector3.UP*.65);camera.fov=55;camera.make_current()
	for frame in 3:await process_frame
	await photograph("both-boarded")
	camera.global_position=ride.car.global_transform*Vector3(0,1.0,.70)
	camera.look_at(ride.car.global_transform*Vector3(0,.85,.1));camera.fov=110
	for frame in 3:await process_frame
	await photograph("seated-interior")
	camera.free();game.camera.make_current();game.app_focused=true
func board_diagnostic(game:Node,ride:Node)->void:
	var session:Node=game.world_vehicle
	session.activation.select_for_entry(game.player.position,ride.identity())
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.player.position+Vector3.UP,ride.car.position,7,[game.player.get_rid(),ride.car.get_rid()]))
	print("BOARD_DIAGNOSTIC ",{"active":ride.world_active(),"can_interact":session.can_interact(),"reachable":session.reachable(game,ride.identity()),"phase":ride.state.phase,"seated":ride.state.seated,"player":game.player.position,"car":ride.car.position,"parked_views":session.activation.parked_views.size(),"selected":session.car_identity,"selected_body":session.car,"driving":session.driving,"ray":hit})
func watch(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000;var next_log:=0
	var prior_frame:=Time.get_ticks_usec()
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
		var now:=Time.get_ticks_usec()
		if frame_ms.size()<30000:frame_ms.append((now-prior_frame)/1000.0)
		prior_frame=now
		if Time.get_ticks_msec()>=next_log:
			next_log=Time.get_ticks_msec()+5000
			var ride:Node=current_scene.trader.ride
			var item:Dictionary={"ms":Time.get_ticks_msec(),"phase":ride.state.phase,"driver":ride.state.driver_position,"status":ride.status_text,"walk":ride.navigator.status(1),"command":ride.command,"car":ride.car.position if is_instance_valid(ride.car) else Vector3.INF,"speed":ride.car.linear_velocity.length() if is_instance_valid(ride.car) else 0,"ready":ride.probe_ready,"clear":ride.probe_clear}
			item.probe_reason=ride.probe_reason
			samples.append(item);print("RIDE_SAMPLE ",item)
			FileAccess.open(folder.path_join("samples.json"),FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
	return predicate.call()
func walk_player_to_car(game:Node,ride:Node)->bool:
	var nav:Node3D=ClassDB.instantiate("NativeActorNavigator");game.add_child(nav);nav.configure(1);nav.set_exclusions([game.player.get_rid()])
	var goal:Vector3=game.world_vehicle.safe_exit_for(game,ride.car,game.player.get_rid())
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline and game.player.position.distance_to(goal)>.6:
		await physics_frame
		var delta:=1.0/Engine.physics_ticks_per_second
		nav.set_agent(1,game.player.position,goal,0,true);nav.advance(delta,game._actor_collision_ready,Callable())
		var direction:Vector3=nav.steering_target(1)-game.player.position;direction.y=0
		var velocity:Vector3=direction.normalized()*2.8 if nav.state(1)=="following" else Vector3.ZERO
		if not nav.guard_motion(1,velocity,velocity.length()*delta):velocity=Vector3.ZERO
		game.player.velocity=Vector3(velocity.x,0 if game.player.is_on_floor() else game.player.velocity.y-20*delta,velocity.z)
		game.movement.move_grounded(game.player,delta)
		game.camera.look_at(ride.car.position+Vector3.UP*.6)
	print("PLAYER_WALK ",nav.status(1)," position=",game.player.position," goal=",goal)
	var ok:bool=game.player.position.distance_to(goal)<.7;nav.free();return ok
func finish()->void:
	if not frame_ms.is_empty():
		frame_ms.sort()
		FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify({"samples":frame_ms.size(),"p95_ms":frame_ms[mini(frame_ms.size()-1,int(frame_ms.size()*.95))],"worst_ms":frame_ms[-1],"fps_cap":Engine.max_fps,"measurement":"wall-clock process-frame intervals","scope":"Offscreen source run under the world's active FPS policy; includes harness sampling and excludes startup/player fixture walking"},"  "))
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test never captures the user's pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"private copied world closes durably")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("TRADER_RIDE_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
